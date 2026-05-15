#!/usr/bin/env bash
# Runs inside the posthogos-builder container (or natively on Arch).
# Assembles a writable build tree from upstream/ + overlay/, then invokes
# buildiso.sh to produce the ISO.
#
# Expected env:
#   KEEP_BUILD=1       (default 0) keep build/ work tree after build
#   FAST_BUILD=1       (default 0) use zstd not xz for squashfs

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
# Belt-and-suspenders chmod before the rm: pacstrap leaves
# /etc/ca-certificates/extracted/cadir/ as mode 0555 (read-only dir), and
# plain `rm -rf` can't unlink files inside a 0555 parent dir → "Permission
# denied" spam, aborted reset, doomed build. The end-of-build cleanup also
# does this, but it only fires on success + KEEP_BUILD=0. Interrupted or
# KEEP_BUILD'd builds leave the 0555 dirs around for the NEXT run to trip on.
if [ -d "$build_dir" ]; then
    chmod -R u+w "$build_dir" 2>/dev/null || true
fi
rm -rf "$build_dir"
mkdir -p "$build_dir"
# git archive gives the checked-in tree without the submodule .git pointer.
git -C upstream archive --format=tar HEAD | tar -x -C "$build_dir"

echo "==> Generating derived assets (resampled wallpapers, slideshow, splash)"
"$repo_root/scripts/build-assets.sh"

echo "==> Applying overlay/ → archiso/"
# Previously gated on `find overlay ... | grep -q .` to skip the rsync
# when overlay/ was empty. Under `set -euo pipefail` that pipeline
# returned non-zero (grep -q exits early → SIGPIPEs find → find non-zero
# → pipefail propagates), so the guard ALWAYS evaluated false and the
# rsync was silently skipped on every build. Symptom: nothing under
# overlay/ ever landed on the ISO (autostart entries, /usr/local/bin/
# scripts, /etc/skel dotfiles, LAF defaults, the welcome QML, …) while
# overlay-generated/ files came through fine because they use a plain
# `[ -d ]` check with no piping. Just rsync unconditionally; an empty
# source dir is a harmless no-op.
if [ -d overlay ]; then
    rsync -a --info=stats1 \
        --exclude='.gitkeep' --exclude='README.md' \
        overlay/ "$build_dir/archiso/"
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
