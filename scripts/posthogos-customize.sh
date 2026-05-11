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
# Theme descriptor must already be at /usr/share/plymouth/themes/$BRAND/$BRAND.plymouth
# from the overlay. We point plymouthd at it, then regenerate the initramfs.
if [ -f "/usr/share/plymouth/themes/$BRAND/$BRAND.plymouth" ]; then
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
    log "Plymouth theme '$BRAND' not present (no .plymouth descriptor) — leaving CachyOS default"
fi

# ---- Calamares branding --------------------------------------------------
# Only flip the branding pointer if our branding dir actually has a
# branding.desc. Otherwise Calamares would fail to start.
if [ -f /etc/calamares/settings.conf ] && \
   [ -f "/usr/share/calamares/branding/$BRAND/branding.desc" ]; then
    log "Patching /etc/calamares/settings.conf branding: $BRAND"
    sed -i "s/^branding:.*/branding: $BRAND/" /etc/calamares/settings.conf
else
    log "Calamares branding '$BRAND' not present — leaving CachyOS default"
fi

# ---- SDDM theme ----------------------------------------------------------
# Requires both metadata.desktop and Main.qml to be a working theme.
if [ -f "/usr/share/sddm/themes/$BRAND/Main.qml" ] && \
   [ -f "/usr/share/sddm/themes/$BRAND/metadata.desktop" ]; then
    log "Setting SDDM current theme: $BRAND"
    mkdir -p /etc/sddm.conf.d
    cat >/etc/sddm.conf.d/10-posthogos-branding.conf <<EOF
[Theme]
Current=$BRAND
EOF
else
    log "SDDM theme '$BRAND' not present (Main.qml missing) — leaving CachyOS default"
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
