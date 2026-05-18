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
# chmod before rm: pacstrap leaves some dirs (e.g. ca-certificates/extracted/cadir)
# at 0555, which blocks `rm -rf`. End-of-build cleanup handles this too but only
# fires on success + KEEP_BUILD=0.
[ -d "$build_dir" ] && chmod -R u+w "$build_dir" 2>/dev/null || true
rm -rf "$build_dir"
mkdir -p "$build_dir"
git -C upstream archive --format=tar HEAD | tar -x -C "$build_dir"

echo "==> Generating derived assets (resampled wallpapers, slideshow, splash)"
"$repo_root/scripts/build-assets.sh"

# Paths the posthogos-* packages own. Skip them in the overlay rsync so
# the unowned overlay copies don't clobber the pacstrap'd files (the
# whole point of Phase 1.5). Same list applied to overlay/ and
# overlay-generated/; mismatched excludes are no-ops.
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
    # posthogos-welcome
    --exclude='/airootfs/usr/local/bin/posthogos-welcome'
    --exclude='/airootfs/usr/share/posthogos/welcome.qml'
    --exclude='/airootfs/usr/share/applications/posthogos-welcome.desktop'
    --exclude='/airootfs/etc/xdg/autostart/posthogos-welcome.desktop'
    # posthogos-config
    --exclude='/airootfs/etc/skel/.zshrc'
    --exclude='/airootfs/etc/skel/.gitconfig'
    --exclude='/airootfs/etc/skel/.config/ghostty/'
    --exclude='/airootfs/etc/skel/.config/zellij/'
)

echo "==> Applying overlay/ → archiso/ (pkg-owned paths excluded; pacstrapped instead)"
# Don't gate on `find overlay | grep -q .` under set -o pipefail — grep
# exits early, SIGPIPEs find, the guard always evaluates false and the
# whole rsync silently skips. Empty source dir is a harmless no-op anyway.
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
# pre-build.sh added the packages to packages_desktop.x86_64 and
# registered the [posthogos] file:// repo in archiso/pacman.conf, so
# mkarchiso below will resolve them via this dir.
echo "==> Building posthogos-* packages + local pacman repo"
pkg_repo="$build_dir/posthogos-localrepo"
mkdir -p "$pkg_repo"
# makepkg refuses root. chown the dirs it writes to: each PKGBUILD's
# src/+pkg/, overlay-generated (branding's build() reruns build-assets.sh),
# and the local repo dir (PKGDEST + repo-add output).
id -u builder >/dev/null 2>&1 || useradd -m -s /bin/bash builder
chown -R builder packages overlay-generated "$pkg_repo"

# ── Signing setup ─────────────────────────────────────────────────────
# Import the secret key into builder's gpg keyring so makepkg/repo-add
# can --sign. Hard-fail under CI without a key: end-user pacman.conf is
# SigLevel=Required, so a release ISO that shipped unsigned would brick
# `pacman -Syu`.
makepkg_sign_flags=()
repo_add_sign_flags=()
if [ -n "${POSTHOGOS_PACKAGER_KEY:-}" ] && [ -n "${POSTHOGOS_PACKAGER_KEY_FPR:-}" ]; then
    echo "==> Importing PostHog packager signing key (fpr ${POSTHOGOS_PACKAGER_KEY_FPR:0:8}…)"
    install -d -o builder -g builder -m 0700 /home/builder/.gnupg
    # Loopback pinentry for the (currently no-passphrase) key, in case we
    # ever switch to one — non-interactive container can't pop pinentry.
    echo 'allow-loopback-pinentry' \
        | sudo -u builder tee /home/builder/.gnupg/gpg-agent.conf >/dev/null
    echo "$POSTHOGOS_PACKAGER_KEY" | sudo -u builder gpg --batch --import
    echo "$POSTHOGOS_PACKAGER_KEY_FPR:6:" | sudo -u builder gpg --import-ownertrust
    makepkg_sign_flags=(--sign --key "$POSTHOGOS_PACKAGER_KEY_FPR")
    repo_add_sign_flags=(--sign --key "$POSTHOGOS_PACKAGER_KEY_FPR")
elif [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "ERROR: CI build needs POSTHOGOS_PACKAGER_KEY + POSTHOGOS_PACKAGER_KEY_FPR." >&2
    echo "       End-user pacman.conf is SigLevel=Required; unsigned packages would brick pacman -Syu." >&2
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

# Run as builder so --sign finds the key in /home/builder/.gnupg
# (running as root looks in /root/.gnupg → empty → "key does not exist").
(cd "$pkg_repo" && sudo -u builder repo-add "${repo_add_sign_flags[@]}" \
    posthogos.db.tar.zst ./*.pkg.tar.zst)
echo "==> Local pacman repo ready:"
ls -lh "$pkg_repo"

# Import signing key into the build container's pacman-key keyring
# (separate from builder's gpg keyring used by makepkg above) so
# pacstrap can verify the signed db. Without this, [posthogos] would
# need SigLevel=Never instead of Optional.
if [ ${#repo_add_sign_flags[@]} -gt 0 ] && [ -f packages/posthogos-keyring/posthogos.gpg ]; then
    echo "==> Importing posthogos signing key into build-container pacman keyring"
    pacman-key --add packages/posthogos-keyring/posthogos.gpg
    pacman-key --lsign-key "$POSTHOGOS_PACKAGER_KEY_FPR"
fi

# Mirror the repo into out/pkgs/ so CI's gh-pages publish + release upload
# don't have to rebuild it.
mkdir -p "$out_dir/pkgs"
cp -a "$pkg_repo"/. "$out_dir/pkgs/"

echo "==> Installing chroot hook"
# mkarchiso runs airootfs/root/customize_airootfs.sh at squashfs assembly time.
install -D -m 0755 scripts/posthogos-customize.sh \
    "$build_dir/archiso/airootfs/root/customize_airootfs.sh"

echo "==> Running upstream buildiso.sh"
cd "$build_dir"
# No -w: buildiso.sh's cleanup does `rm -rf` over the build tree which
# fails on 0555 dirs left by package post-install hooks. We clean up below.
buildiso_args=(-p desktop -v)

# Needs root for bind mounts. sudo -E only when not already root (native path).
if [ "$(id -u)" -eq 0 ]; then
    ./buildiso.sh "${buildiso_args[@]}"
else
    sudo -E ./buildiso.sh "${buildiso_args[@]}"
fi

echo "==> Copying ISO to out/"
shopt -s nullglob globstar
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
    chmod -R u+w "$build_dir" 2>/dev/null || true  # 0555 dirs block rm
    rm -rf "$build_dir"
fi

echo "==> Done. ISO(s) at:"
ls -lh "$out_dir"/*.iso
