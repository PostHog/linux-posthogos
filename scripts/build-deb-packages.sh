#!/usr/bin/env bash
#
# Build .deb equivalents of the portable PosthogOS packages and assemble a
# signed APT repository, for Debian/Ubuntu-based KDE systems.
#
# We do NOT re-stage files from overlay/. Instead we repackage the already
# built pacman packages (`*.pkg.tar.zst`): a pacman package is just a tar of
# the staged file tree plus a few dotfile metadata members, so reusing it
# keeps the .deb byte-for-byte identical to what Arch ships and avoids
# duplicating each PKGBUILD's package() copy logic. The only divergence is
# Debian's `/usr/bin` policy: posthogos-scripts ships executables under
# /usr/local/bin on Arch, so we relocate *our own* binaries (and rewrite the
# absolute paths that reference them) to /usr/bin here.
#
# Inputs (env):
#   PKG_SRC_DIR          dir holding posthogos-*.pkg.tar.zst (default: out/pkgs)
#   DEB_OUT_DIR          apt repo output dir                 (default: out/deb)
#   POSTHOGOS_PKGVER     version, e.g. 0.2.0 (default: derived from git tag)
#   POSTHOGOS_PACKAGER_KEY      armored GPG secret key; signs the Release (optional)
#   POSTHOGOS_PACKAGER_KEY_FPR  fingerprint of that key (required if KEY set)
#
# Without a signing key the repo is published unsigned (local dev); apt then
# needs `[trusted=yes]` in the sources line. CI always sets the key.
#
# Tooling: dpkg-deb, dpkg-scanpackages (dpkg-dev), apt-ftparchive (apt-utils),
# gzip, zstd-aware tar, gpg. Runs on a Debian/Ubuntu host or in bin/build-deb's
# container — not on macOS directly.

set -euo pipefail

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Only the portable, non-Arch-specific packages port to Debian. The keyring,
# welcome (Qt), config (/etc/skel dotfiles) and the meta stay Arch-only.
DEB_PACKAGES=(posthogos-branding posthogos-scripts)

# Repo identity.
REPO_ORIGIN="PosthogOS"
REPO_SUITE="stable"
REPO_COMPONENT="main"
# Both packages are Architecture: all (data + shell scripts, nothing compiled),
# so the same _all.deb serves every arch. apt still resolves per-arch, though:
# an arm64 client only reads binary-arm64/Packages. So we publish the identical
# index under each arch dir below rather than building anything per-arch.
REPO_ARCHES=(amd64 arm64)

PKG_SRC_DIR="${PKG_SRC_DIR:-out/pkgs}"
DEB_OUT_DIR="${DEB_OUT_DIR:-out/deb}"

for tool in dpkg-deb dpkg-scanpackages apt-ftparchive gzip tar; do
    command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done

# --- Resolve version ------------------------------------------------------
# Mirror the PKGBUILD pkgver() logic so a standalone run matches the repo tag.
if [ -z "${POSTHOGOS_PKGVER:-}" ]; then
    v=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
    [ -n "$v" ] || v="0.0.0~dev.$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    POSTHOGOS_PKGVER="$v"
fi
# Debian version grammar forbids '_' (the pacman normalization) — map it to
# '~' so pre-releases (0.0.1_alpha → 0.0.1~alpha) still sort *before* the
# final release, as Debian intends. Strip a leading 'v' if present.
DEB_VER="${POSTHOGOS_PKGVER#v}"
DEB_VER="${DEB_VER//_/\~}-1"   # -1 = Debian revision
log "Debian package version: $DEB_VER (from POSTHOGOS_PKGVER=$POSTHOGOS_PKGVER)"

# --- Per-package control metadata ----------------------------------------
# Depends are kept empty so apt never refuses to install on a minimal box;
# the parent themes / tools are Recommends/Suggests (best-effort, Debian
# names). snap-pac is intentionally absent — it's a pacman-only hook.
control_for() {
    local pkg="$1" size="$2"
    case "$pkg" in
    posthogos-branding)
        cat <<EOF
Package: posthogos-branding
Version: $DEB_VER
Architecture: all
Maintainer: PostHog <hey@posthog.com>
Installed-Size: $size
Section: x11
Priority: optional
Recommends: papirus-icon-theme
Suggests: plasma-workspace, plasma-desktop
Homepage: https://github.com/posthog/linux-posthogos
Description: PosthogOS visual identity (icons, wallpapers, Plasma look-and-feel, fonts, sounds)
 Icons, wallpapers, Plasma look-and-feel (Light + Dark), colour schemes,
 SDDM and Plymouth themes, fonts, sound theme and Konsole profile that make
 up the PosthogOS desktop. Apply with plasma-apply-lookandfeel after install.
EOF
        ;;
    posthogos-scripts)
        cat <<EOF
Package: posthogos-scripts
Version: $DEB_VER
Architecture: all
Maintainer: PostHog <hey@posthog.com>
Installed-Size: $size
Section: utils
Priority: optional
Recommends: posthogos-branding
Suggests: snapper, btrfs-progs, grub-btrfs, fastfetch
Homepage: https://github.com/posthog/linux-posthogos
Description: PosthogOS system scripts (firstrun, snapper-init, toolkit-install, neohog)
 First-login look-and-feel activator (autostart), snapper initialisation,
 the dev-toolkit installer and the neohog fastfetch wrapper. The firstrun
 autostart entry applies the PosthogOS theme to a KDE Plasma session.
EOF
        ;;
    *) die "no control template for $pkg" ;;
    esac
}

# --- Relocate our own /usr/local/bin binaries to /usr/bin (Debian policy) -
# Only posthogos-scripts ships under /usr/local/bin. We move the tree and
# rewrite references to *our* binaries (posthogos-*, neohog, papirus-folders)
# only — NOT third-party tools that toolkit-install drops into /usr/local/bin
# at runtime (op, asdf), which legitimately belong there.
relocate_local_bin() {
    local root="$1"
    [ -d "$root/usr/local/bin" ] || return 0
    log "  relocating /usr/local/bin → /usr/bin"
    install -d "$root/usr/bin"
    cp -a "$root/usr/local/bin/." "$root/usr/bin/"
    rm -rf "$root/usr/local"

    # Rewrite absolute paths to our binaries in every shipped text file
    # (scripts, .desktop autostart, systemd units). Targeted patterns leave
    # /usr/local/bin/{op,asdf} runtime-install references untouched.
    local f
    while IFS= read -r -d '' f; do
        sed -i \
            -e 's#/usr/local/bin/posthogos-#/usr/bin/posthogos-#g' \
            -e 's#/usr/local/bin/neohog#/usr/bin/neohog#g' \
            -e 's#/usr/local/bin/papirus-folders#/usr/bin/papirus-folders#g' \
            "$f"
    done < <(find "$root/usr/bin" "$root/etc" "$root/usr/lib/systemd" -type f -print0 2>/dev/null)
}

# --- Build one .deb from a .pkg.tar.zst -----------------------------------
build_one_deb() {
    local pkg="$1" pool_dir="$2"
    local src
    src=$(ls -1t "$PKG_SRC_DIR/$pkg"-*.pkg.tar.zst 2>/dev/null | head -n1 || true)
    [ -n "$src" ] || die "no $pkg-*.pkg.tar.zst found in $PKG_SRC_DIR (run bin/build first)"
    log "$pkg ← $(basename "$src")"

    local root
    root=$(mktemp -d)
    chmod 755 "$root"   # mktemp -d is 0700; the package root maps to / perms
    # zstd-aware extraction; --zstd is supported by GNU tar with zstd present.
    tar --zstd -xf "$src" -C "$root"
    # Drop pacman metadata members.
    rm -f "$root"/.PKGINFO "$root"/.BUILDINFO "$root"/.MTREE "$root"/.INSTALL "$root"/.CHANGELOG

    # Move pacman's per-package license dir to the Debian convention.
    if [ -d "$root/usr/share/licenses/$pkg" ]; then
        install -d "$root/usr/share/doc/$pkg"
        cp -a "$root/usr/share/licenses/$pkg/." "$root/usr/share/doc/$pkg/" 2>/dev/null || true
        rm -rf "$root/usr/share/licenses"
    fi

    relocate_local_bin "$root"

    # Installed-Size is in KiB (Debian policy).
    local size
    size=$(du -ks "$root" | cut -f1)

    install -d "$root/DEBIAN"
    control_for "$pkg" "$size" > "$root/DEBIAN/control"

    install -d "$pool_dir"
    local out="$pool_dir/${pkg}_${DEB_VER}_all.deb"
    # --root-owner-group: files owned by root:root without needing fakeroot.
    dpkg-deb --root-owner-group --build "$root" "$out" >/dev/null
    rm -rf "$root"
    log "  → $out"
}

# --- Assemble the apt repo ------------------------------------------------
# Flat pool + dists/<suite>/<component>/binary-<arch>/Packages, signed Release.
main() {
    rm -rf "$DEB_OUT_DIR"
    local pool_dir="$DEB_OUT_DIR/pool/$REPO_COMPONENT/p"
    local dist_dir="$DEB_OUT_DIR/dists/$REPO_SUITE"
    install -d "$pool_dir"

    local pkg
    for pkg in "${DEB_PACKAGES[@]}"; do
        build_one_deb "$pkg" "$pool_dir/$pkg"
    done

    log "Generating Packages index (scanned once, published per arch)"
    local packages_tmp
    packages_tmp=$(mktemp)
    ( cd "$DEB_OUT_DIR" && dpkg-scanpackages --multiversion pool /dev/null ) \
        > "$packages_tmp"
    local arch bin_dir
    for arch in "${REPO_ARCHES[@]}"; do
        bin_dir="$dist_dir/$REPO_COMPONENT/binary-$arch"
        install -d "$bin_dir"
        cp "$packages_tmp" "$bin_dir/Packages"
        gzip -9 -kf "$bin_dir/Packages"
    done
    rm -f "$packages_tmp"

    log "Generating Release"
    local release_tmp
    release_tmp=$(mktemp)
    ( cd "$DEB_OUT_DIR" && apt-ftparchive \
        -o "APT::FTPArchive::Release::Origin=$REPO_ORIGIN" \
        -o "APT::FTPArchive::Release::Label=$REPO_ORIGIN" \
        -o "APT::FTPArchive::Release::Suite=$REPO_SUITE" \
        -o "APT::FTPArchive::Release::Codename=$REPO_SUITE" \
        -o "APT::FTPArchive::Release::Architectures=${REPO_ARCHES[*]}" \
        -o "APT::FTPArchive::Release::Components=$REPO_COMPONENT" \
        release "dists/$REPO_SUITE" ) > "$release_tmp"
    mv "$release_tmp" "$dist_dir/Release"

    # --- Sign the Release (InRelease + Release.gpg) ------------------------
    if [ -n "${POSTHOGOS_PACKAGER_KEY:-}" ]; then
        [ -n "${POSTHOGOS_PACKAGER_KEY_FPR:-}" ] \
            || die "POSTHOGOS_PACKAGER_KEY set but POSTHOGOS_PACKAGER_KEY_FPR is not"
        log "Signing Release with ${POSTHOGOS_PACKAGER_KEY_FPR:0:8}…"
        export GNUPGHOME
        GNUPGHOME=$(mktemp -d)
        chmod 700 "$GNUPGHOME"
        echo "$POSTHOGOS_PACKAGER_KEY" | gpg --batch --import 2>/dev/null
        gpg --batch --yes --pinentry-mode loopback --default-key "$POSTHOGOS_PACKAGER_KEY_FPR" \
            --clearsign -o "$dist_dir/InRelease" "$dist_dir/Release"
        gpg --batch --yes --pinentry-mode loopback --default-key "$POSTHOGOS_PACKAGER_KEY_FPR" \
            --detach-sign --armor -o "$dist_dir/Release.gpg" "$dist_dir/Release"
        rm -rf "$GNUPGHOME"
        unset GNUPGHOME
    else
        log "POSTHOGOS_PACKAGER_KEY unset → publishing UNSIGNED repo (apt needs [trusted=yes])"
    fi

    # Publish the public key so users can `signed-by=` it. Sourced from the
    # keyring package (a `gpg --export` binary keyring — valid for signed-by).
    if [ -f packages/posthogos-keyring/posthogos.gpg ]; then
        cp packages/posthogos-keyring/posthogos.gpg "$DEB_OUT_DIR/posthogos.gpg"
    fi

    log "APT repo ready at $DEB_OUT_DIR"
    find "$DEB_OUT_DIR" -type f | sort | sed 's/^/    /'
}

main "$@"
