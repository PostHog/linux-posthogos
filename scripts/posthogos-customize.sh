#!/usr/bin/env bash
# Runs inside the airootfs chroot, after pacstrap, before squashfs assembly.
# Used for things the static overlay can't express:
#   - mkinitcpio -P (must run AFTER Plymouth theme is in place)
#   - sed-patch /etc/calamares/settings.conf (file owned by cachyos-calamares
#     pkg; we shadow the branding value rather than overwrite the whole file)
#   - icon / gtk caches
#   - service enables
#
# Idempotent: safe to re-run on retry.

set -euo pipefail

log() { printf '[posthogos-customize] %s\n' "$*"; }

BRAND="posthogos"

# ---- Plymouth ------------------------------------------------------------
# Theme files must already be in /usr/share/plymouth/themes/$BRAND/ from the
# overlay. We point plymouthd at it, then regenerate the initramfs so the
# theme is embedded.
if [ -d "/usr/share/plymouth/themes/$BRAND" ]; then
    log "Configuring Plymouth theme: $BRAND"
    mkdir -p /etc/plymouth
    cat >/etc/plymouth/plymouthd.conf <<EOF
[Daemon]
Theme=$BRAND
ShowDelay=0
EOF
    if command -v plymouth-set-default-theme >/dev/null; then
        plymouth-set-default-theme -R "$BRAND" || log "WARN: plymouth-set-default-theme failed"
    else
        log "Running mkinitcpio -P to embed plymouth theme"
        mkinitcpio -P
    fi
else
    log "Plymouth theme dir missing — skipping (overlay not wired up yet?)"
fi

# ---- Calamares branding --------------------------------------------------
# Patch the branding key in place. cachyos-calamares-next ships this file;
# we just flip the pointer.
if [ -f /etc/calamares/settings.conf ]; then
    log "Patching /etc/calamares/settings.conf branding: $BRAND"
    sed -i "s/^branding:.*/branding: $BRAND/" /etc/calamares/settings.conf
fi

# ---- SDDM theme ----------------------------------------------------------
if [ -d "/usr/share/sddm/themes/$BRAND" ]; then
    log "Setting SDDM current theme: $BRAND"
    mkdir -p /etc/sddm.conf.d
    cat >/etc/sddm.conf.d/10-posthogos-branding.conf <<EOF
[Theme]
Current=$BRAND
EOF
fi

# Make sure SDDM is the active display manager (CachyOS does this already,
# but double-checking is cheap).
systemctl enable sddm.service 2>/dev/null || true

# ---- Caches --------------------------------------------------------------
log "Refreshing desktop / icon / gtk caches"
[ -d /usr/share/icons ] && find /usr/share/icons -maxdepth 1 -mindepth 1 -type d \
    -exec gtk-update-icon-cache -q -t -f {} \; 2>/dev/null || true
update-desktop-database -q 2>/dev/null || true
glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || true

log "Done."
