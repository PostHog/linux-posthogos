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
    -e 's|^iso_publisher=.*|iso_publisher="PosthogOS <https://github.com/Georges-Antoine/linux-posthogos>"|' \
    -e 's|^iso_application=.*|iso_application="PosthogOS Live/Rescue DVD"|' \
    "$pf"
rm -f "${pf}.bak"

log "Identity now:"
grep -E '^(iso_name|iso_label|iso_publisher|iso_application)=' "$pf"

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

log "Done."
