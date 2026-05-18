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

# Paths that posthogos-* pacman packages own. We pacstrap those packages
# below, so these paths land on the ISO with proper pacman ownership —
# and we MUST skip them in the overlay rsync, otherwise the unowned
# overlay files would clobber the pacstrap'd ones and reintroduce the
# first-install file collision dance (`pacman -S --overwrite='*'`).
# Excludes are applied to both overlay/ and overlay-generated/; rsync
# silently ignores excludes that don't match.
pkg_owned_excludes=(
    # posthogos-branding
    --exclude='/airootfs/usr/share/color-schemes/'
    --exclude='/airootfs/usr/share/plasma/look-and-feel/com.posthog.posthogos'
    --exclude='/airootfs/usr/share/plasma/look-and-feel/com.posthog.posthogos.dark'
    --exclude='/airootfs/usr/share/konsole/PosthogOS.colorscheme'
    --exclude='/airootfs/usr/share/konsole/PosthogOS.profile'
    --exclude='/airootfs/usr/share/sddm/themes/posthogos'
    --exclude='/airootfs/usr/share/wallpapers/Posthogos*'
    --exclude='/airootfs/usr/share/plymouth/themes/posthogos'
    --exclude='/airootfs/usr/share/icons/'
    --exclude='/airootfs/usr/share/fonts/posthogos'
    --exclude='/airootfs/usr/share/sounds/posthogos'
    # posthogos-scripts
    --exclude='/airootfs/usr/local/bin/neohog'
    --exclude='/airootfs/usr/local/bin/papirus-folders'
    --exclude='/airootfs/usr/local/bin/posthogos-firstrun.sh'
    --exclude='/airootfs/usr/local/bin/posthogos-firstrun-rescue.sh'
    --exclude='/airootfs/usr/local/bin/posthogos-snapper-init'
    --exclude='/airootfs/usr/local/bin/posthogos-toolkit-install'
    --exclude='/airootfs/etc/xdg/autostart/posthogos-firstrun.desktop'
    --exclude='/airootfs/etc/systemd/system/posthogos-snapper-init.service'
    --exclude='/airootfs/etc/systemd/system/posthogos-firstrun-rescue.service'
)

echo "==> Applying overlay/ → archiso/ (pkg-owned paths excluded; pacstrapped instead)"
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
        "${pkg_owned_excludes[@]}" \
        overlay/ "$build_dir/archiso/"
fi

echo "==> Applying overlay-generated/ → archiso/ (pkg-owned paths excluded; pacstrapped instead)"
if [ -d overlay-generated ]; then
    rsync -a --info=stats1 \
        "${pkg_owned_excludes[@]}" \
        overlay-generated/ "$build_dir/archiso/"
fi

echo "==> Running pre-build patches"
"$repo_root/scripts/pre-build.sh" "$build_dir"

# ── Build posthogos-* pacman packages + local repo ────────────────────────
# Phase 1.5: instead of overlay-copying branding files onto the ISO
# (where they end up owned by no package), build the posthogos-* .pkg.tar.zst
# files here, expose them as a local file:// pacman repo, and let mkarchiso
# pacstrap them. Result: every owned file on the installed system is
# pacman-owned from day one. `pacman -Syu` brings in new versions cleanly
# with no --overwrite dance.
#
# pre-build.sh appended `posthogos-keyring` + `posthogos-branding` to
# packages_desktop.x86_64 and registered the [posthogos] file:// repo in
# archiso/pacman.conf above, so mkarchiso below will find these packages.
echo "==> Building posthogos-* packages + local pacman repo"
pkg_repo="$build_dir/posthogos-localrepo"
mkdir -p "$pkg_repo"
# makepkg refuses to run as root. Create a builder user if absent
# (idempotent for repeated --keep-build runs) and chown the dirs it
# needs to write to: packages/*/ (each PKGBUILD's src/, pkg/) and
# overlay-generated (posthogos-branding's build() re-invokes build-assets.sh).
id -u builder >/dev/null 2>&1 || useradd -m -s /bin/bash builder
chown -R builder packages overlay-generated

# ── Signing setup ─────────────────────────────────────────────────────
# When CI supplies the PostHog packager secret key, import it into the
# builder's keyring and sign every package + the repo db. Local dev (no
# key) builds unsigned packages; the build-time [posthogos] repo is at
# SigLevel = Optional TrustAll so unsigned is fine. End-user pacman.conf
# (written by posthogos-customize.sh) uses SigLevel = Required — so a
# release ISO built WITHOUT the key in CI would produce a broken end-user
# update path. Hard-fail in that case to catch misconfigured CI early.
makepkg_sign_flags=()
repo_add_sign_flags=()
if [ -n "${POSTHOGOS_PACKAGER_KEY:-}" ] && [ -n "${POSTHOGOS_PACKAGER_KEY_FPR:-}" ]; then
    echo "==> Importing PostHog packager signing key (fpr ${POSTHOGOS_PACKAGER_KEY_FPR:0:8}…)"
    # gpg writes to builder's GNUPGHOME (=/home/builder/.gnupg). Pre-create
    # with right perms; let gpg auto-init the rest.
    install -d -o builder -g builder -m 0700 /home/builder/.gnupg
    # Loopback pinentry: lets a passphrase-protected key still sign in a
    # non-interactive container if we ever switch to one. No-op when the
    # key has no passphrase (current default).
    echo 'allow-loopback-pinentry' \
        | sudo -u builder tee /home/builder/.gnupg/gpg-agent.conf >/dev/null
    echo "$POSTHOGOS_PACKAGER_KEY" | sudo -u builder gpg --batch --import
    echo "$POSTHOGOS_PACKAGER_KEY_FPR:6:" | sudo -u builder gpg --import-ownertrust
    makepkg_sign_flags=(--sign --key "$POSTHOGOS_PACKAGER_KEY_FPR")
    repo_add_sign_flags=(--sign --key "$POSTHOGOS_PACKAGER_KEY_FPR")
elif [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "ERROR: running under CI but POSTHOGOS_PACKAGER_KEY / _FPR not set." >&2
    echo "       End-user pacman.conf will have SigLevel=Required and reject unsigned packages." >&2
    echo "       Set the GH secret POSTHOGOS_PACKAGER_KEY + repo variable POSTHOGOS_PACKAGER_KEY_FPR." >&2
    exit 1
else
    echo "==> POSTHOGOS_PACKAGER_KEY unset → building unsigned (local dev mode)"
fi

for pkgdir in packages/*/; do
    pkg=$(basename "$pkgdir")
    echo "==> makepkg $pkg"
    (
        cd "$pkgdir"
        sudo -u builder env PKGDEST="$pkg_repo" \
            makepkg "${makepkg_sign_flags[@]}" -df --noconfirm
    )
done

# repo-add accumulates all entries in a single posthogos.db.tar.zst, and
# generates the symlinks pacman fetches (posthogos.db, posthogos.files).
# --sign also produces posthogos.db.tar.zst.sig, verified by end-user
# pacman when [posthogos] is set to SigLevel = Required (not
# DatabaseOptional).
(cd "$pkg_repo" && repo-add "${repo_add_sign_flags[@]}" posthogos.db.tar.zst ./*.pkg.tar.zst)
echo "==> Local pacman repo ready:"
ls -lh "$pkg_repo"

# Mirror the repo into out/pkgs/ so the CI gh-pages publish + release-asset
# upload steps don't have to re-build it.
mkdir -p "$out_dir/pkgs"
cp -a "$pkg_repo"/. "$out_dir/pkgs/"

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
