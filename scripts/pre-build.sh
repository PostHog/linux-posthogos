#!/usr/bin/env bash
# Narrow sed-patches against the writable build tree, after overlay rsync,
# before buildiso.sh. Patching (vs. shadowing) lets upstream changes flow
# through on rebase.
#
# Argv: $1 = path to the build directory (e.g. /work/build)

set -euo pipefail

build_dir="${1:?Usage: $0 <build-dir>}"
cd "$build_dir"

log() { printf '[pre-build] %s\n' "$*"; }

# Target arch (set by bin/build / CI; default x86_64, the only working
# target today). x86_64 leaves profiledef + util-iso byte-for-byte upstream;
# other arches get retargeted below.
iso_arch="${BUILD_ARCH:-x86_64}"

# --- ISO identity in archiso/profiledef.sh --------------------------------
pf="archiso/profiledef.sh"
[ -f "$pf" ] || { echo "Missing $pf" >&2; exit 1; }

log "Patching $pf identity fields"
sed -i.bak \
    -e 's|^iso_name=.*|iso_name="posthogos"|' \
    -e 's|^iso_label="COS_|iso_label="POSTHOGOS_|' \
    -e 's|^iso_publisher=.*|iso_publisher="PosthogOS <https://github.com/posthog/linux-posthogos>"|' \
    -e 's|^iso_application=.*|iso_application="PosthogOS Live/Rescue DVD"|' \
    "$pf"
rm -f "${pf}.bak"

log "Identity now:"
grep -E '^(iso_name|iso_label|iso_publisher|iso_application)=' "$pf"

# --- Target arch retarget (non-x86_64 only) -------------------------------
# x86_64 is left untouched (upstream profiledef already sets it). For other
# arches: point profiledef's arch at the real target and drop the x86-only
# squashfs BCJ filter ('-Xbcj' 'x86'), which mksquashfs rejects elsewhere.
# (FAST_BUILD rewrites the whole tool-options line below, dropping BCJ anyway.)
if [ "$iso_arch" != "x86_64" ]; then
    log "Retargeting profiledef arch → $iso_arch (and dropping x86 squashfs BCJ filter)"
    sed -i.bak \
        -e 's|^arch=.*|arch="'"$iso_arch"'"|' \
        -e "s|'-Xbcj' 'x86' ||" \
        "$pf"
    rm -f "${pf}.bak"
    grep -E '^(arch|airootfs_image_tool_options)=' "$pf"
fi

# --- Fast compression for dev iteration -----------------------------------
# FAST_BUILD=1: xz → zstd, 5-10x faster, ~25% larger. Local-only.
if [ "${FAST_BUILD:-0}" = "1" ]; then
    log "FAST_BUILD=1 → switching squashfs compressor to zstd"
    sed -i.bak \
        "s|^airootfs_image_tool_options=.*|airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '3' '-b' '1M')|" \
        "$pf"
fi

# --- Suppress macOS-host xattr noise --------------------------------------
# Docker Desktop on macOS leaks com.apple.* xattrs through bind mounts,
# producing "Unrecognised xattr prefix" warnings from mksquashfs for
# every file. Harmless, but noisy.
log "Adding -xattrs-exclude for com.apple.* to squashfs options"
sed -i.bak \
    "s|airootfs_image_tool_options=(\(.*\))|airootfs_image_tool_options=(\1 '-xattrs-exclude' '^com\\\.apple\\\.')|" \
    "$pf"
rm -f "${pf}.bak"
grep '^airootfs_image_tool_options=' "$pf"

# --- Boot menu titles -----------------------------------------------------
# Case-sensitive replace: "CachyOS" only appears in user-visible strings;
# internal identifiers ("cachyos", "linux-cachyos") stay untouched.
log "Rebranding boot menu titles (CachyOS → PosthogOS)"
boot_files=()
for d in archiso/grub archiso/syslinux archiso/efiboot; do
    [ -d "$d" ] || continue
    while IFS= read -r -d '' f; do boot_files+=("$f"); done < \
        <(find "$d" -type f \( -name '*.cfg' -o -name '*.conf' \) -print0)
done
if [ ${#boot_files[@]} -gt 0 ]; then
    # -i.bak works on both GNU and BSD sed; clean up the backups after.
    sed -i.bak 's/CachyOS/PosthogOS/g' "${boot_files[@]}"
    find archiso/grub archiso/syslinux archiso/efiboot \
        -type f -name '*.bak' -delete 2>/dev/null || true
    log "Patched ${#boot_files[@]} boot config file(s)"
fi

# --- Extra packages -------------------------------------------------------
# Appending (vs. shadowing the file) lets upstream additions flow through.
# archiso names package lists packages_<profile>.<arch>; resolve by arch.
pkglist="archiso/packages_desktop.${iso_arch}"
if [ -f "$pkglist" ]; then
    posthogos_pkgs=(
        # PosthogOS packages from the local file:// repo we register below.
        posthogos-keyring    # bootstraps trust for SigLevel=Required updates
        posthogos-branding   # icons, wallpapers, LAF, fonts, sounds, themes
        posthogos-scripts    # firstrun, snapper-init, toolkit-install, neohog
        posthogos-welcome    # welcome window + Qt6 launcher
        posthogos-config     # /etc/skel dotfiles
        posthogos            # meta-package depending on the above

        # System packages.
        inter-font           # Matter SQ analog; primary system body font
        papirus-icon-theme   # icon parent theme (PosthogOS icons inherit)
        qt6-declarative      # qml6 + QtQuick.Controls (Qt6 consolidates these)
        qqc2-breeze-style    # Breeze QML style; without it welcome.qml exits 2
        xcb-util-cursor      # Qt 6.5+ xcb plugin dep; missing → plasmashell
                             # SIGABRTs at QGuiApplication init on TCG (no WAYLAND_DISPLAY).
        pkgconf              # build-time deps discovery (Qt6 cflags/libs)
        flatpak              # secondary app channel (Flathub set up in customize.sh)
        snapper              # btrfs snapshots; initialized by posthogos-snapper-init
        snap-pac             # pacman hooks: snapshot before/after every -S/U/R
        grub-btrfs           # GRUB submenu entries for each snapper snapshot
        fuse2                # libfuse2 for AppImages (e.g. posthog-code)
        ghostty              # default terminal (replaces Konsole in pins)
        nodejs               # dev-toolkit's `npm install -g` for AI CLIs
        npm
    )
    log "Appending PosthogOS packages to $pkglist"
    for pkg in "${posthogos_pkgs[@]}"; do
        grep -qxF "$pkg" "$pkglist" || echo "$pkg" >> "$pkglist"
    done

    # Drop CachyOS packages we replace.
    posthogos_remove_pkgs=(
        cachyos-hello   # → posthogos-welcome
    )
    log "Removing CachyOS packages we're replacing"
    for pkg in "${posthogos_remove_pkgs[@]}"; do
        if grep -qxF "$pkg" "$pkglist"; then
            sed -i.bak "/^${pkg}$/d" "$pkglist"
            rm -f "${pkglist}.bak"
            log "  removed: $pkg"
        fi
    done

    # --- FAST_BUILD: drop alternate kernels -------------------------------
    # CachyOS ships 6 kernels (linux-cachyos + -lts + -zfs/-nvidia-open
    # variants of each). Each triggers `mkinitcpio -P` during pacstrap +
    # again on plymouth-set-default-theme. Drop alternates locally;
    # CI keeps them for ZFS-root + proprietary-NVIDIA install paths.
    if [ "${FAST_BUILD:-0}" = "1" ]; then
        fast_drop_kernels=(
            linux-cachyos-lts
            linux-cachyos-lts-zfs
            linux-cachyos-lts-nvidia-open
            linux-cachyos-nvidia-open
            linux-cachyos-zfs
        )
        log "FAST_BUILD=1 → dropping ${#fast_drop_kernels[@]} alternate kernels (keeping linux-cachyos only)"
        for k in "${fast_drop_kernels[@]}"; do
            if grep -qxF "$k" "$pkglist"; then
                sed -i.bak "/^${k}$/d" "$pkglist"
                log "  dropped: $k"
            fi
        done
        rm -f "${pkglist}.bak"

        # Marker for customize.sh to skip the slow plymouth initramfs regen.
        # customize.sh deletes the marker after reading.
        log "  writing /etc/posthogos-fast-build marker for customize hook"
        mkdir -p archiso/airootfs/etc
        echo 1 > archiso/airootfs/etc/posthogos-fast-build

        # Repoint bootloader entries that reference the now-missing LTS
        # kernel. Without this, the default entry (or any LTS-titled
        # fallback) silently fails to load and loops back to the menu.
        log "  repointing LTS bootloader entries to linux-cachyos"
        boot_targets=(
            archiso/grub/grub.cfg
            archiso/grub/loopback.cfg
        )
        for ef in archiso/efiboot/loader/entries/*.conf; do
            [ -f "$ef" ] && boot_targets+=("$ef")
        done
        for f in "${boot_targets[@]}"; do
            [ -f "$f" ] || continue
            sed -i.bak \
                -e 's|vmlinuz-linux-cachyos-lts|vmlinuz-linux-cachyos|g' \
                -e 's|initramfs-linux-cachyos-lts|initramfs-linux-cachyos|g' \
                "$f"
            rm -f "${f}.bak"
        done
    fi
fi

# --- Register local posthogos pacman repo for mkarchiso pacstrap ----------
# Build-time repo only. in-container-build.sh populates it after this
# script returns. End-user [posthogos] (pointing at github.io) is set up
# separately by customize.sh inside the chroot.
build_pacman_conf="archiso/pacman.conf"
if [ -f "$build_pacman_conf" ] && ! grep -q '^\[posthogos\]' "$build_pacman_conf"; then
    log "Registering [posthogos] file:// repo at $build_dir/posthogos-localrepo"
    cat >>"$build_pacman_conf" <<EOF

[posthogos]
SigLevel = Optional
Server = file://${build_dir}/posthogos-localrepo
EOF
fi

# --- util-iso.sh post-build fixups ----------------------------------------
# Upstream bugs:
#   1. `chown $USER`: $USER unset in container → invalid syntax
#   2. Hardcoded `cachyos-` filename prefix; mkarchiso writes `posthogos-`
#   3. gen_iso_fn embeds "cachyos" and a date suffix; we want a stable name
if [ -f util-iso.sh ]; then
    log "Patching util-iso.sh (chown, iso filename prefix, gen_iso_fn, drop date suffix)"
    sed -i.bak \
        -e 's|sudo chown \$USER \$outFolder|true # chown removed by pre-build.sh|' \
        -e 's|/cachyos-\$(date|/posthogos-$(date|' \
        -e 's|vars+=("cachyos")|vars+=("posthogos")|' \
        -e 's|vars+=("\$(date +%y%m%d)")|# date suffix removed by pre-build.sh|' \
        util-iso.sh
    rm -f util-iso.sh.bak

    # util-iso.sh hardcodes the x86_64 arch in three spots: the source
    # package list (packages_desktop.x86_64 → packages.x86_64), the
    # pkglist.x86_64.txt it copies out, and the -x86_64.iso name mkarchiso
    # emits. mkarchiso derives those from profiledef's arch=, so retarget
    # them to match. Guarded so x86_64 stays byte-for-byte upstream.
    if [ "$iso_arch" != "x86_64" ]; then
        log "Retargeting util-iso.sh hardcoded x86_64 filenames → $iso_arch"
        sed -i.bak "s/x86_64/${iso_arch}/g" util-iso.sh
        rm -f util-iso.sh.bak
    fi
fi

# --- buildiso.sh: kill the misleading EXIT trap ---------------------------
# Upstream registers `trap 'trap_exit EXIT "An unknown error has occurred"' EXIT`
# which fires on EVERY exit (including exit 0), unconditionally printing
# the error message and confusing CI logs. The ERR trap (line above it)
# stays so real errors still surface.
if [ -f buildiso.sh ]; then
    log "Patching buildiso.sh (drop spurious EXIT trap)"
    sed -i.bak "/^trap 'trap_exit EXIT/d" buildiso.sh
    rm -f buildiso.sh.bak
fi

log "Done."
