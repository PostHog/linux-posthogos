#!/usr/bin/env bash
# Runs against the writable build tree BEFORE buildiso.sh, after overlay rsync.
# Used for narrow sed-patches against upstream files we don't want to fully
# shadow (because shadowing risks dropping new upstream entries on rebase).
#
# Files touched here:
#   archiso/profiledef.sh                   ISO identity
#   archiso/grub/*.cfg                      GRUB menu titles
#   archiso/syslinux/*.cfg                  syslinux menu titles
#   archiso/efiboot/loader/entries/*.conf   systemd-boot entry titles
#   util-iso.sh                             upstream wrapper bugs:
#                                            - chown $USER fails when $USER unset
#                                            - mv source pattern hardcodes cachyos-
#                                            - gen_iso_fn hardcodes cachyos-
#
# Argv: $1 = path to the build directory (e.g. /work/build)

set -euo pipefail

build_dir="${1:?Usage: $0 <build-dir>}"
cd "$build_dir"

log() { printf '[pre-build] %s\n' "$*"; }

# --- ISO identity in archiso/profiledef.sh --------------------------------
# Narrow sed: replace only the four identity strings. Leaves file_permissions
# and everything else untouched so upstream changes flow through.
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

# --- Fast compression for dev iteration -----------------------------------
# FAST_BUILD=1 swaps xz (slow, dense) for zstd (5-10x faster, ~25% larger).
# Use for local iteration; leave unset for ship-quality compression.
if [ "${FAST_BUILD:-0}" = "1" ]; then
    log "FAST_BUILD=1 → switching squashfs compressor to zstd"
    sed -i.bak \
        "s|^airootfs_image_tool_options=.*|airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '3' '-b' '1M')|" \
        "$pf"
fi

# --- Suppress macOS-host xattr noise --------------------------------------
# On macOS hosts the bind-mount leaks com.apple.* xattrs through to the
# container, producing "Unrecognised xattr prefix" warnings from mksquashfs
# for every file. Harmless (those xattrs are useless on Linux) but noisy.
# Tell mksquashfs to skip them.
log "Adding -xattrs-exclude for com.apple.* to squashfs options"
sed -i.bak \
    "s|airootfs_image_tool_options=(\(.*\))|airootfs_image_tool_options=(\1 '-xattrs-exclude' '^com\\\.apple\\\.')|" \
    "$pf"
rm -f "${pf}.bak"
grep '^airootfs_image_tool_options=' "$pf"

# --- Boot menu titles -----------------------------------------------------
# "CachyOS" (mixed case) only appears in user-visible strings in the boot
# configs. Internal identifiers use lowercase "cachyos" and the package name
# "linux-cachyos", neither of which matches the case-sensitive replace below.
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
# Append PosthogOS-required packages to the package list. Appending (rather
# than shadowing the file) lets upstream additions flow through on rebase.
pkglist="archiso/packages_desktop.x86_64"
if [ -f "$pkglist" ]; then
    posthogos_pkgs=(
        inter-font           # Free Matter SQ analog; primary system body font
        papirus-icon-theme   # Friendlier folders + place/app icons than Breeze
        qt6-declarative      # qml6 + ALL Qt6 QML modules including QtQuick.Controls
                             # (unlike Qt5 where qt5-quickcontrols2 was separate, the
                             #  Qt6 modules are consolidated into this one package on Arch)
        qqc2-breeze-style    # Breeze QML style for QtQuick.Controls. Without this,
                             # QtQuick.Controls picks Breeze as the default style on Plasma
                             # and fails to load org.kde.breeze, killing welcome.qml (exit 2)
        xcb-util-cursor      # Qt 6.5+ requires this for the xcb (X11) platform plugin.
                             # Without it, the plugin refuses to load and any Qt6 app
                             # falling back to xcb (e.g. plasmashell when WAYLAND_DISPLAY
                             # is unset, common in QEMU TCG without GPU passthrough)
                             # SIGABRTs at QGuiApplication init with "no Qt platform
                             # plugin could be initialized". Crash-loops the whole
                             # session; symptom is black screen with only autostart
                             # apps that already inherited a good env still visible.
        pkgconf              # pkg-config implementation. Chroot compile of
                             # /usr/src/posthogos-welcome-launcher.cpp uses it
                             # to discover Qt6 cflags/libs
        flatpak              # Secondary app distribution channel for
                             # sandboxed GUI apps (Slack, Spotify, Zoom, etc.)
                             # System-wide Flathub registered in customize.sh.
                             # Plasma's Discover auto-detects Flatpak and adds
                             # the source to its catalog when the binary is
                             # installed, with no extra discover-flatpak-backend
                             # package needed in modern Plasma.
        snapper              # Btrfs snapshot manager. With Calamares now
                             # defaulting installs to btrfs (see partition.conf
                             # patch in customize.sh), snapper handles
                             # automatic snapshots + rollback. Initialized on
                             # first installed boot by posthogos-snapper-init.
        snap-pac             # Pacman hooks that snapshot before/after every
                             # `pacman -S/U/R` op, giving us an automatic rollback target
                             # for any package change that breaks the system.
        grub-btrfs           # Generates GRUB submenu entries for every
                             # snapper snapshot so you can boot into a
                             # snapshot from the bootloader if the running
                             # system can't reach a desktop.
        fuse2                # libfuse2 (AppImages like posthog-code self-mount via this)
        ghostty              # Default terminal emulator (replaces Konsole in pins)
        nodejs               # JS runtime. Needed for the dev-toolkit installer
                             # to land Gemini CLI + OpenAI Codex via `npm install -g`.
                             # Also a dep many JS dev workflows assume regardless.
        npm                  # Node package manager. Same rationale as nodejs.

        # Dev tooling (AI CLIs, modern Unix tools, containers, asdf,
        # Tailscale, mitmproxy, op, zsh+pure) is opt-in via
        # /usr/local/bin/posthogos-toolkit-install. papirus-folders is
        # AUR-only so we vendor v1.14.0 under /usr/local/bin/.
    )
    log "Appending PosthogOS packages to $pkglist"
    for pkg in "${posthogos_pkgs[@]}"; do
        grep -qxF "$pkg" "$pkglist" || echo "$pkg" >> "$pkglist"
    done

    # Packages we don't want installed. Removing here saves disk + boot time
    # and makes sure our replacements (e.g. posthogos-welcome) are the only
    # implementations in play.
    posthogos_remove_pkgs=(
        cachyos-hello   # Replaced by /usr/local/bin/posthogos-welcome (QML)
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
    # CachyOS's desktop preset installs SIX kernels: linux-cachyos plus its
    # -lts twin, plus -nvidia-open and -zfs variants of each. Every kernel
    # triggers its own `mkinitcpio -P` during pacstrap and another full
    # regen later when our customize hook runs plymouth-set-default-theme,
    # so a vanilla build prints the "Running build hook: [archiso_pxe_*] →
    # [block] → [filesystems]" sequence 6-12 times. For local iteration
    # where one bootable kernel is all you need to verify a change, drop
    # the alternates. CI builds (FAST_BUILD unset) keep the full set so
    # shipped ISOs still cover ZFS-root + proprietary-NVIDIA install paths.
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

        # Marker for the chroot hook to skip the slow plymouth initramfs
        # regen. customize.sh probes for this file and deletes it after
        # reading, so it doesn't ship in the final squashfs.
        log "  writing /etc/posthogos-fast-build marker for customize hook"
        mkdir -p archiso/airootfs/etc
        echo 1 > archiso/airootfs/etc/posthogos-fast-build

        # Repoint all linux-cachyos-lts references in the bootloader
        # configs to the main linux-cachyos kernel. Upstream's GRUB,
        # systemd-boot, and loopback configs include menu entries (and
        # in systemd-boot's case the DEFAULT entry) that load
        # vmlinuz-linux-cachyos-lts + initramfs-linux-cachyos-lts.img.
        # With FAST_BUILD dropping the LTS kernel package, those files
        # don't exist on the ISO and any user who picks the default
        # entry (or any LTS-titled fallback entry) gets a silent bootloader
        # failure that bounces them back to the boot menu in an endless
        # loop. Repoint instead of delete-menus so the menu shapes
        # match the full-build ISOs.
        log "  repointing LTS bootloader entries to linux-cachyos"
        boot_targets=(
            archiso/grub/grub.cfg
            archiso/grub/loopback.cfg
        )
        # systemd-boot entries split into one file per entry; glob them.
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

# --- util-iso.sh post-build fixups ----------------------------------------
# Upstream's util-iso.sh has four issues we need to patch:
#   1. `sudo chown $USER $outFolder`: $USER unset in container → invalid syntax
#   2. `mv "$outFolder/$_profile/cachyos-<date>-x86_64.iso" ...`: hardcoded
#      cachyos- prefix, but mkarchiso writes ${iso_name}-...iso = posthogos-...
#   3. `gen_iso_fn` adds "cachyos" to renamed filename, should be "posthogos"
#   4. `gen_iso_fn` appends $(date +%y%m%d) to the filename, but we want a stable
#      "posthogos-desktop-linux.iso" name so each build just overwrites the
#      previous output instead of accumulating dated copies in out/.
if [ -f util-iso.sh ]; then
    log "Patching util-iso.sh (chown, iso filename prefix, gen_iso_fn, drop date suffix)"
    sed -i.bak \
        -e 's|sudo chown \$USER \$outFolder|true # chown removed by pre-build.sh|' \
        -e 's|/cachyos-\$(date|/posthogos-$(date|' \
        -e 's|vars+=("cachyos")|vars+=("posthogos")|' \
        -e 's|vars+=("\$(date +%y%m%d)")|# date suffix removed by pre-build.sh|' \
        util-iso.sh
    rm -f util-iso.sh.bak
fi

log "Done."
