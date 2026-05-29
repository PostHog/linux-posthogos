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

# ---- PosthogOS pacman repo ----------------------------------------------
# Register [posthogos] so installed systems get package updates via
# `pacman -Syu`. SigLevel=Required works from first boot because
# posthogos-keyring's .install hook locally signed the packager key.
# Appended (not prepended) so CachyOS's higher-priority repos still win
# for anything ambiguous; we only publish `posthogos-*` names anyway.
if ! grep -q '^\[posthogos\]' /etc/pacman.conf; then
    log "Registering [posthogos] pacman repo"
    cat >>/etc/pacman.conf <<'EOF'

[posthogos]
SigLevel = Required
Server = https://posthog.github.io/linux-posthogos/$arch
EOF
fi

# ---- OS identity ---------------------------------------------------------
# Owned by upstream packages (filesystem, lsb-release), so pacstrap
# refuses to overwrite; write them post-pacstrap.
log "Writing /etc/os-release"
cat >/etc/os-release <<'EOF'
NAME="PosthogOS"
PRETTY_NAME="PosthogOS"
ID=posthogos
ID_LIKE="cachyos arch"
BUILD_ID=rolling
ANSI_COLOR="38;2;255;100;0"
HOME_URL="https://github.com/posthog/linux-posthogos"
DOCUMENTATION_URL="https://github.com/posthog/linux-posthogos"
SUPPORT_URL="https://github.com/posthog/linux-posthogos/issues"
BUG_REPORT_URL="https://github.com/posthog/linux-posthogos/issues"
LOGO=posthogos
EOF

log "Writing /etc/lsb-release"
cat >/etc/lsb-release <<'EOF'
LSB_VERSION=1.4
DISTRIB_ID=PosthogOS
DISTRIB_RELEASE=rolling
DISTRIB_DESCRIPTION="PosthogOS"
EOF

log "Writing /etc/hostname"
echo "posthogos" > /etc/hostname

# ---- /etc/motd -----------------------------------------------------------
# util-iso.sh's generate_motd() runs *before* this chroot hook and writes a
# CachyOS-branded welcome banner. Overwrite it.
log "Writing /etc/motd"
cat >/etc/motd <<'EOF'

  Welcome to PosthogOS, a CachyOS-based spin with PostHog branding.

  Live environment ready. Pick "Install PosthogOS" from the desktop to
  install to disk, or explore the live session.

  Source: https://github.com/posthog/linux-posthogos
  Issues: https://github.com/posthog/linux-posthogos/issues

EOF

# ---- liveuser home + XDG base dirs --------------------------------------
# Subdirs must exist with liveuser:liveuser ownership BEFORE first login,
# or ksycoca fails and Plasma crashes with "Error loading Applet: package
# does not exist". UID/GID directly (nsswitch may not resolve `liveuser`
# in this chroot context).
log "Provisioning /home/liveuser with XDG base dirs (uid=1000)"
install -d -o 1000 -g 1000 -m 0755 \
    /home/liveuser \
    /home/liveuser/.cache \
    /home/liveuser/.config \
    /home/liveuser/.local \
    /home/liveuser/.local/share \
    /home/liveuser/.local/state \
    /home/liveuser/Desktop \
    /home/liveuser/Documents \
    /home/liveuser/Downloads \
    /home/liveuser/Pictures
chown -R 1000:1000 /home/liveuser
ls -ld /home/liveuser /home/liveuser/.cache  # log the resulting state
# /home itself must be traversable.
[ -d /home ] && chmod 0755 /home

# ---- liveuser identity: name "Max" + hedgehog avatar --------------------
# Display name comes from the GECOS field — accountsservice surfaces it as
# RealName for the greeter / lock screen / Kickoff. usermod edits
# /etc/passwd directly, so it works even though nsswitch may not resolve
# `liveuser` by name in this chroot. The avatar PNG + AccountsService
# descriptor (Icon=) ship via overlay-generated/ + overlay/; here we also
# drop ~/.face.icon for SDDM-style greeters that bypass accountsservice.
log "Setting liveuser display name to 'Max'"
usermod -c Max liveuser 2>/dev/null || log "WARN: usermod -c Max failed"
avatar="/var/lib/AccountsService/icons/liveuser"
if [ -f "$avatar" ] && [ -d /home/liveuser ]; then
    log "Seeding /home/liveuser/.face.icon from AccountsService avatar"
    install -m 0644 -o 1000 -g 1000 "$avatar" /home/liveuser/.face.icon
else
    log "Avatar $avatar absent; skipping .face.icon (Max will use default icon)"
fi

# Fontconfig cache: writable by all. Otherwise every Plasma startup spams
# "Fontconfig error: No writable cache directories".
install -d -m 0755 /var/cache/fontconfig

# Re-chmod in the chroot: Docker Desktop's bind-mount perm propagation on
# macOS is unreliable, so the +x bit on overlay scripts gets lost.
if [ -d /usr/local/bin ]; then
    chmod +x /usr/local/bin/* 2>/dev/null || true
fi
if [ -d /opt/posthog-code ]; then
    chmod +x /opt/posthog-code/*.AppImage 2>/dev/null || true
fi

# ---- Suppress CachyOS Hello popup ---------------------------------------
# cachyos-hello auto-pops on every login. Shadow its /etc/xdg autostart
# entry with a user-level Hidden=true (XDG spec: user wins over /etc).
log "Suppressing cachyos-hello autostart"
hello_override='[Desktop Entry]
Type=Application
Name=CachyOS Hello
Hidden=true
'
# /etc/skel for future Calamares-installed users:
install -d -m 0755 /etc/skel/.config/autostart
printf '%s' "$hello_override" > /etc/skel/.config/autostart/cachyos-hello.desktop
# /home/liveuser for the live ISO user (home already populated by now):
if [ -d /home/liveuser ]; then
    install -d -o 1000 -g 1000 -m 0755 /home/liveuser/.config/autostart
    printf '%s' "$hello_override" > /home/liveuser/.config/autostart/cachyos-hello.desktop
    chown 1000:1000 /home/liveuser/.config/autostart/cachyos-hello.desktop
fi

# ---- Plasma + GTK defaults for new users ---------------------------------
# cachyos-kde-settings owns these /etc/skel paths, so we can't pre-stage
# them via the overlay. Writing post-pacstrap overwrites cleanly.
log "Writing /etc/skel Plasma + GTK defaults"
mkdir -p /etc/skel/.config/gtk-3.0 /etc/skel/.config/gtk-4.0

cat >/etc/skel/.config/kdeglobals <<'EOF'
[General]
ColorScheme=PosthogosLight
Name=PosthogOS Light
font=Inter,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular
fixed=DejaVu Sans Mono,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular
menuFont=Inter,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular
smallestReadableFont=Inter,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular
toolBarFont=Inter,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,Regular
# Default terminal: set both keys (legacy + Plasma 6) for full coverage.
TerminalApplication=ghostty
TerminalService=com.mitchellh.ghostty.desktop

[KDE]
LookAndFeelPackage=com.posthog.posthogos
widgetStyle=Breeze
SingleClick=false

[Icons]
Theme=PosthogOS

# Sound theme at /usr/share/sounds/posthogos/. Falls through to the
# freedesktop default for events we don't override.
[Sounds]
Theme=posthogos
EOF

# Tell System Settings which LAF is active. Without this file the KCM
# shows nothing selected until firstrun applies it.
mkdir -p /etc/skel/.config/kdedefaults
echo 'com.posthog.posthogos' > /etc/skel/.config/kdedefaults/package

for v in gtk-3.0 gtk-4.0; do
    cat >"/etc/skel/.config/$v/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=Breeze
gtk-icon-theme-name=PosthogOS
gtk-font-name=Inter 11
gtk-cursor-theme-name=breeze_cursors
gtk-application-prefer-dark-theme=false
EOF
done

# Konsole: use the branded profile by default.
cat >/etc/skel/.config/konsolerc <<'EOF'
[Desktop Entry]
DefaultProfile=PosthogOS.profile

[MainWindow]
MenuBar=Disabled
ToolBarsMovable=Disabled
EOF
# Also for the existing live user
if [ -d /home/liveuser ]; then
    install -d -o 1000 -g 1000 -m 0755 /home/liveuser/.config
    cp /etc/skel/.config/konsolerc /home/liveuser/.config/konsolerc
    chown 1000:1000 /home/liveuser/.config/konsolerc
fi

# ---- Seed liveuser's home with /etc/skel additions ----------------------
# liveuser predates the overlay rsync, so /etc/skel additions don't
# auto-propagate (skel is consulted at user-creation only). `cp -an`
# (no-clobber) avoids trampling state on re-runs. Trailing /. handles dotfiles.
if [ -d /home/liveuser ] && [ -d /etc/skel ]; then
    log "Seeding /home/liveuser with /etc/skel contents (dotfiles, configs)"
    cp -an /etc/skel/. /home/liveuser/ 2>&1 | sed 's/^/  /' || true
    chown -R 1000:1000 /home/liveuser
fi

# ---- Plymouth ------------------------------------------------------------
# Theme descriptor comes from the overlay (posthogos-branding ships it).
# Point plymouthd at it, then regenerate the initramfs.
if [ -f "/usr/share/plymouth/themes/$BRAND/$BRAND.plymouth" ]; then
    mkdir -p /etc/plymouth
    cat >/etc/plymouth/plymouthd.conf <<EOF
[Daemon]
Theme=$BRAND
ShowDelay=0
EOF

    # FAST_BUILD skips the ~10 min initramfs regen (unbranded plymouth
    # splash for a few seconds before SDDM, in exchange).
    if [ -f /etc/posthogos-fast-build ]; then
        log "Configuring Plymouth theme: $BRAND (FAST_BUILD: config-only, no initramfs regen)"
        rm -f /etc/posthogos-fast-build   # don't ship the marker
    elif command -v plymouth-set-default-theme >/dev/null; then
        log "Configuring Plymouth theme: $BRAND (running -R to embed into initramfs)"
        plymouth-set-default-theme -R "$BRAND" || log "WARN: plymouth-set-default-theme failed"
    else
        log "Configuring Plymouth theme: $BRAND (running mkinitcpio -P)"
        mkinitcpio -P
    fi
else
    log "Plymouth theme '$BRAND' not present (no .plymouth descriptor); leaving CachyOS default"
fi

# ---- Calamares branding --------------------------------------------------
# cachyos-calamares-next ships settings.conf under /usr/share/, vanilla
# Calamares uses /etc/. Probe both. Only flip if our branding.desc
# actually exists, or Calamares fails to start.
cal_settings=""
for candidate in /usr/share/calamares/settings.conf /etc/calamares/settings.conf; do
    [ -f "$candidate" ] && cal_settings="$candidate" && break
done
if [ -n "$cal_settings" ] && [ -f "/usr/share/calamares/branding/$BRAND/branding.desc" ]; then
    log "Patching $cal_settings branding: $BRAND"
    sed -i "s/^branding:.*/branding: $BRAND/" "$cal_settings"
    log "  result: $(grep '^branding:' "$cal_settings")"
else
    log "Calamares branding '$BRAND' not present at any known settings.conf path; leaving CachyOS default"
fi

# ---- Calamares: default to btrfs ---------------------------------------
# Auto-install default: btrfs (snapper / snap-pac / grub-btrfs need it).
# Manual partitioning still offers ext4/xfs/f2fs.
for part_conf in /usr/share/calamares/modules/partition.conf /etc/calamares/modules/partition.conf; do
    if [ -f "$part_conf" ]; then
        log "Patching $part_conf → defaultFileSystemType: btrfs"
        sed -i 's|^defaultFileSystemType:.*|defaultFileSystemType: btrfs|' "$part_conf"
        log "  result: $(grep '^defaultFileSystemType:' "$part_conf")"
        break
    fi
done

# ---- Calamares: default hostname ----------------------------------------
# users.conf ships with template "cachyos-${cpu}", which the installer
# surfaces as the default answer to "What is the name of this computer?"
# (e.g. cachyos-x8664). Rebrand to posthogos-${cpu} so it reads
# posthogos-x8664 (or the relevant arch) while keeping the arch suffix.
for users_conf in /usr/share/calamares/modules/users.conf /etc/calamares/modules/users.conf; do
    if [ -f "$users_conf" ]; then
        log "Patching $users_conf → hostname template: posthogos-\${cpu}"
        sed -i 's|^\(\s*\)template:.*cachyos-\${cpu}.*|\1template: "posthogos-${cpu}"|' "$users_conf"
        log "  result: $(grep 'template:' "$users_conf")"
        break
    fi
done

# ---- Display manager: plasma-login-manager (plasmalogin) ----------------
# Upstream KDE's SDDM fork with a Plasma-native greeter. Config must live
# at /etc/plasmalogin.conf, but /etc/plasmalogin.conf.d/ is silently ignored
# (upstream bug). WallpaperPluginId is required: without it, the greeter
# bails with "Error loading Applet: package  does not exist".
log "Writing /etc/plasmalogin.conf (autologin + branded wallpaper)"
cat >/etc/plasmalogin.conf <<'EOF'
[Autologin]
User=liveuser
Session=plasma.desktop
Relogin=false

[Users]
MinimumUid=100
MaximumUid=60000

[Greeter]
WallpaperPluginId=org.kde.image

[Greeter][Wallpaper][org.kde.image][General]
Image=file:///usr/share/wallpapers/PosthogosKeyboardGarden/contents/images_dark/3840x2160.png
PreviewImage=file:///usr/share/wallpapers/PosthogosKeyboardGarden/contents/images_dark/3840x2160.png
FillMode=2
EOF

# ---- Curate the wallpaper picker -----------------------------------------
# Prune CachyOS-flavored wallpapers that dilute the brand in System
# Settings. Keep ours + stock Breeze.
log "Pruning non-PosthogOS / non-Breeze wallpapers"
if [ -d /usr/share/wallpapers ]; then
    for wp in /usr/share/wallpapers/*/; do
        name=$(basename "$wp")
        case "$name" in
            Posthogos*) ;;                              # ours
            Breeze|Next|Path|Volna|Lake|Mountain|Pollen|Patak|Cluster|Kay|Cascade|Flow) ;;  # Breeze stock
            *)
                log "  removing /usr/share/wallpapers/$name"
                rm -rf "$wp"
                ;;
        esac
    done
fi

# ---- Papirus folder color ------------------------------------------------
# Blue → orange via the vendored AUR helper at /usr/local/bin/papirus-folders.
PAPIRUS_COLOR=orange
if [ -d /usr/share/icons/Papirus-Light ] && [ -x /usr/local/bin/papirus-folders ]; then
    log "Recoloring Papirus-Light folders → $PAPIRUS_COLOR (papirus-folders)"
    /usr/local/bin/papirus-folders -t Papirus-Light -C "$PAPIRUS_COLOR" -v \
        || log "WARN: papirus-folders failed"
fi

# Plasma 6's Discover auto-detects Flatpak when the binary's present;
# no separate discover-flatpak-backend package needed.
if command -v flatpak >/dev/null; then
    log "Registering Flathub as a system-wide Flatpak remote"
    flatpak remote-add --system --if-not-exists \
        flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
        2>&1 | sed 's/^/  /' \
        || log "WARN: flathub remote-add failed (Discover will still find it on first run)"
fi

# ---- Caches --------------------------------------------------------------
log "Refreshing desktop / icon / gtk / font caches"
[ -d /usr/share/icons ] && find /usr/share/icons -maxdepth 1 -mindepth 1 -type d \
    -exec gtk-update-icon-cache -q -t -f {} \; 2>/dev/null || true
update-desktop-database -q 2>/dev/null || true
glib-compile-schemas /usr/share/glib-2.0/schemas/ 2>/dev/null || true
fc-cache -f /usr/share/fonts 2>/dev/null || true   # register branded fonts

log "Done."
