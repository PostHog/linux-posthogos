#!/usr/bin/env bash
# Runs against the writable build tree BEFORE buildiso.sh, after overlay rsync.
# Used for narrow sed-patches against upstream files we don't want to fully
# shadow (because shadowing risks dropping new upstream entries on rebase).
#
# Files touched here:
#   archiso/profiledef.sh                 — ISO identity
#   archiso/grub/*.cfg                    — GRUB menu titles
#   archiso/syslinux/*.cfg                — syslinux menu titles
#   archiso/efiboot/loader/entries/*.conf — systemd-boot entry titles
#   util-iso.sh                           — upstream wrapper bugs:
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
# "linux-cachyos" — neither matches the case-sensitive replace below.
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
        fuse2                # libfuse2 — AppImages (e.g. posthog-code) self-mount via this
        ghostty              # Default terminal emulator (replaces Konsole in pins)
        docker               # Docker engine — dep of docker-desktop (.pkg.tar.zst staged via build-assets.sh)
        docker-compose       # Compose plugin alongside docker
        # papirus-folders (the recolor helper) is AUR-only; we vendor the
        # upstream script at overlay/airootfs/usr/local/bin/papirus-folders
        # and invoke it from the chroot hook.
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
fi

# --- util-iso.sh post-build fixups ----------------------------------------
# Upstream's util-iso.sh has four issues we need to patch:
#   1. `sudo chown $USER $outFolder` — $USER unset in container → invalid syntax
#   2. `mv "$outFolder/$_profile/cachyos-<date>-x86_64.iso" ...` — hardcoded
#      cachyos- prefix, but mkarchiso writes ${iso_name}-...iso = posthogos-...
#   3. `gen_iso_fn` adds "cachyos" to renamed filename — should be "posthogos"
#   4. `gen_iso_fn` appends $(date +%y%m%d) to the filename — we want a stable
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
