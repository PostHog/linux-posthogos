#!/usr/bin/env bash
# Runs inside the posthogos-builder container (or natively on Arch).
# Assembles a writable build tree from upstream/ + overlay/, then invokes
# buildiso.sh to produce the ISO.
#
# Expected env:
#   KEEP_BUILD=1       (default 0) — keep build/ work tree after build
#   FAST_BUILD=1       (default 0) — use zstd not xz for squashfs
#   SKIP_AIRFS_CACHE=1 (default 0) — bypass airootfs cache (forces full pacstrap)

set -euo pipefail

cd "$(dirname "$0")/.."
repo_root="$PWD"

if [ ! -d upstream/archiso ]; then
    echo "Missing upstream/archiso. Run: git submodule update --init upstream" >&2
    exit 1
fi

build_dir="$repo_root/build"
out_dir="$repo_root/out"
mkdir -p "$out_dir"

echo "==> Resetting build tree at $build_dir"
rm -rf "$build_dir"
mkdir -p "$build_dir"
# git archive gives the checked-in tree without the submodule .git pointer.
git -C upstream archive --format=tar HEAD | tar -x -C "$build_dir"

echo "==> Generating derived assets (resampled wallpapers, slideshow, splash)"
"$repo_root/scripts/build-assets.sh"

echo "==> Applying overlay/ → archiso/"
if [ -d overlay ] && find overlay -mindepth 1 -not -name '.gitkeep' -not -name 'README.md' \
        | grep -q .; then
    rsync -a --info=stats1 \
        --exclude='.gitkeep' --exclude='README.md' \
        overlay/ "$build_dir/archiso/"
else
    echo "    (overlay/ has no payload files — skipping)"
fi

echo "==> Applying overlay-generated/ → archiso/"
if [ -d overlay-generated ]; then
    rsync -a --info=stats1 overlay-generated/ "$build_dir/archiso/"
fi

echo "==> Running pre-build patches"
"$repo_root/scripts/pre-build.sh" "$build_dir"

echo "==> Installing chroot hook"
# mkarchiso runs airootfs/root/customize_airootfs.sh inside the chroot at
# squashfs assembly time if present at that exact path.
install -D -m 0755 scripts/posthogos-customize.sh \
    "$build_dir/archiso/airootfs/root/customize_airootfs.sh"

# ---- Airootfs cache ------------------------------------------------------
# Cache the post-pacstrap-AND-customize airootfs after a successful build.
# On the next build, if pacstrap-driving inputs are unchanged, restore the
# cached airootfs into build/x86_64/airootfs/, set the make_pacstrap marker
# so mkarchiso skips that ~10-min phase, then re-apply overlay + the
# latest customize hook. mkarchiso runs customize (idempotently — cat>,
# chown, sed, mkinitcpio etc. all safe to re-run), squashfs, and ISO.
#
# Hash inputs are the things that determine pacstrap output. Overlay edits,
# customize edits, branding tweaks intentionally don't invalidate — those
# get re-applied on each build.
cache_dir="$repo_root/.airootfs-cache"
mkdir -p "$cache_dir"
airfs_hash=$(
    cat "$build_dir/archiso/packages_desktop.x86_64" \
        "$build_dir/archiso/bootstrap_packages.x86_64" \
        "$build_dir/archiso/pacman.conf" \
        "$build_dir/archiso/profiledef.sh" 2>/dev/null
    git -C "$repo_root/upstream" rev-parse HEAD 2>/dev/null
)
airfs_hash=$(printf '%s' "$airfs_hash" | sha256sum | cut -c1-16)
airfs_cache="$cache_dir/$airfs_hash.tar.zst"

cache_hit=0
if [ "${SKIP_AIRFS_CACHE:-0}" != "1" ] && [ -f "$airfs_cache" ]; then
    echo "==> Airootfs cache hit: $airfs_hash ($(du -h "$airfs_cache" | cut -f1))"
    mkdir -p "$build_dir/build/x86_64"
    zstd -dc --long=31 "$airfs_cache" \
        | tar -x --numeric-owner --xattrs -C "$build_dir/build/x86_64/" \
            2> >(grep -vE \
                 -e "Cannot llistxattr" \
                 -e "Cannot lsetxattr" \
                 -e "Permission denied" \
                 -e "Too many levels of symbolic links" \
                 -e "Operation not permitted" >&2)
    # Tell mkarchiso pacstrap is done. Customize/squashfs/iso markers are
    # NOT set, so those phases still run → latest customize takes effect.
    touch "$build_dir/build/build.make_pacstrap"
    cache_hit=1

    # Re-apply overlay onto the restored airootfs so the latest overlay
    # files override the cache's snapshot of last build's overlay.
    echo "==> Re-applying overlay onto cached airootfs"
    rsync -a --exclude='.gitkeep' --exclude='README.md' \
        overlay/airootfs/ "$build_dir/build/x86_64/airootfs/" 2>/dev/null || true
    if [ -d overlay-generated/airootfs ]; then
        rsync -a overlay-generated/airootfs/ "$build_dir/build/x86_64/airootfs/"
    fi
    # And re-install the latest customize hook (overlay rsync doesn't touch
    # /root/customize_airootfs.sh — it lives outside airootfs in our layout).
    install -D -m 0755 scripts/posthogos-customize.sh \
        "$build_dir/build/x86_64/airootfs/root/customize_airootfs.sh"
else
    if [ "${SKIP_AIRFS_CACHE:-0}" = "1" ]; then
        echo "==> SKIP_AIRFS_CACHE=1 — running full pacstrap"
    else
        echo "==> Airootfs cache miss ($airfs_hash); will pacstrap and snapshot"
    fi
fi

echo "==> Running upstream buildiso.sh"
cd "$build_dir"
# We never pass -w. buildiso.sh's `-w` cleanup does `rm -rf` over the build
# tree, which fails on dirs left mode 0555 by package post-install hooks
# (notably /etc/ca-certificates/extracted/cadir). Cleanup happens below
# instead, with chmod first.
buildiso_args=(-p desktop -v)

# buildiso.sh requires root for bind mounts. sudo -E preserves env when not
# already root (native path); inside container we run as root already.
if [ "$(id -u)" -eq 0 ]; then
    ./buildiso.sh "${buildiso_args[@]}"
else
    sudo -E ./buildiso.sh "${buildiso_args[@]}"
fi

# Snapshot the airootfs for next build's cache. Only on miss (on hit, the
# cached snapshot is already correct for pacstrap output).
#
# tar emits a lot of `Cannot llistxattr` warnings on dangling symlinks,
# circular icon-theme symlinks, the dbus-daemon-launch-helper placeholder,
# and zfs services with caps the bind-mount can't represent. All
# harmless — the archive itself is valid. Filter the known-harmless
# patterns out of stderr to keep the log readable; real failures (exit
# code) still propagate.
if [ "$cache_hit" = "0" ] && [ -d "$build_dir/build/x86_64/airootfs" ]; then
    echo "==> Snapshotting airootfs → $airfs_cache"
    {
        tar -C "$build_dir/build/x86_64" -cf - --numeric-owner --xattrs airootfs \
            2> >(grep -vE \
                 -e "Cannot llistxattr" \
                 -e "dbus-daemon-launch-helper.*Permission denied" \
                 -e "Too many levels of symbolic links" \
                 -e "Operation not permitted" >&2)
    } | zstd -3 -T0 --long=31 -o "$airfs_cache.tmp" \
        && mv "$airfs_cache.tmp" "$airfs_cache" \
        && echo "    saved $(du -h "$airfs_cache" | cut -f1)" \
        || echo "    WARN: snapshot failed (build still succeeded)"
fi

echo "==> Copying ISO to out/"
shopt -s nullglob globstar
# util-iso.sh places the final renamed ISO at build/out/<profile>/<name>.iso.
iso_files=("$build_dir"/out/**/*.iso)
if [ ${#iso_files[@]} -eq 0 ]; then
    echo "ERROR: no ISO produced under $build_dir/out/" >&2
    exit 1
fi
for f in "${iso_files[@]}"; do
    cp -v "$f" "$out_dir/"
done
chmod 644 "$out_dir"/*.iso 2>/dev/null || true

if [ "${KEEP_BUILD:-0}" != "1" ]; then
    echo "==> Removing build/ (KEEP_BUILD=0)"
    # 0555 dirs (ca-certificates/extracted/cadir) block plain rm; chmod first.
    chmod -R u+w "$build_dir" 2>/dev/null || true
    rm -rf "$build_dir"
fi

echo "==> Done. ISO(s) at:"
ls -lh "$out_dir"/*.iso
