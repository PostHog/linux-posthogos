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
# Register the [posthogos] repo in /etc/pacman.conf so installed systems
# get our package updates (icons, wallpapers, LAF, scripts, ...) via the
# normal `pacman -Syu` flow. Without this entry, every brand iteration
# would require re-downloading the ISO.
#
# SigLevel=Required: every .pkg.tar.zst AND the posthogos.db.tar.zst
# must verify against a key in pacman's trusted keyring. The PostHog
# packager key was pacstrapped via posthogos-keyring and locally signed
# by its .install hook, so verification works from first boot.
#
# Append (don't prepend) so CachyOS's higher-priority repos still win for
# anything ambiguous; the only names we publish are namespaced
# `posthogos-*` so there's no conflict in practice.
if ! grep -q '^\[posthogos\]' /etc/pacman.conf; then
    log "Registering [posthogos] pacman repo"
    cat >>/etc/pacman.conf <<'EOF'

[posthogos]
SigLevel = Required
Server = https://posthog.github.io/linux-posthogos/$arch
EOF
fi

# ---- OS identity ---------------------------------------------------------
# These files are owned by upstream packages (filesystem, lsb-release), so
# we can't pre-stage them in airootfs/etc/ (pacstrap refuses to overwrite).
# Write them here after pacstrap completes.
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
# Plasma session crashes with "Error loading Applet: package  does not
# exist" if ~/.cache isn't writable by liveuser at first login (ksycoca
# fails). The subdirs must exist with liveuser:liveuser ownership BEFORE
# login; chmod on the home root alone isn't enough. Use UID/GID directly
# (nsswitch may not be primed enough for `id liveuser` to work in this
# chroot). Belt-and-suspenders for /etc/tmpfiles.d/posthogos-liveuser.conf,
# which runs at every boot.
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

# Fontconfig cache: writable by all users. Without this, every Plasma startup
# spams "Fontconfig error: No writable cache directories" (we saw 100+ such
# lines in journalctl right before the kded sycoca failure).
install -d -m 0755 /var/cache/fontconfig

# Ensure scripts we ship in /usr/local/bin/ and the PostHog Code AppImage
# are executable. Docker Desktop's bind-mount perm propagation on macOS
# is unreliable, so we re-chmod in the chroot regardless of host perms.
if [ -d /usr/local/bin ]; then
    # posthogos-scripts is the pacman owner of the posthogos-* scripts +
    # neohog + papirus-folders here. Belt + suspenders chmod covers
    # anything else dropped into /usr/local/bin/ by the overlay rsync.
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
# /etc/skel content seeds new accounts on first login. cachyos-kde-settings
# ships its own kdeglobals + gtk settings here, so we can't pre-stage these
# via the overlay (pacstrap refuses conflicting files). Writing post-pacstrap
# overwrites the CachyOS defaults cleanly.
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
# Default terminal emulator. TerminalApplication is the legacy key (used
# by older KIO actions); TerminalService is the Plasma 6 form (.desktop
# basename). Setting both covers Dolphin's "Open Terminal Here", Konsole-
# replacement integrations, and xdg-terminal-exec fallbacks.
TerminalApplication=ghostty
TerminalService=com.mitchellh.ghostty.desktop

[KDE]
LookAndFeelPackage=com.posthog.posthogos
widgetStyle=Breeze
SingleClick=false

[Icons]
Theme=PosthogOS

# Sound theme: events under /usr/share/sounds/posthogos/stereo/ (login,
# logout, message, dialog-*, etc.). Built into the ISO from
# branding/posthogos/sounds/*.ogg by scripts/build-assets.sh. Plasma
# resolves this via libcanberra; falls through to the freedesktop default
# theme for events we don't override.
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
# liveuser was created before the overlay rsync, so /etc/skel additions
# don't auto-propagate (skel is consulted at user-creation time only).
# Mirror them in with `cp -an` (no-clobber) to avoid trampling state on
# re-runs. Calamares-installed users get skel for free post-install.
if [ -d /home/liveuser ] && [ -d /etc/skel ]; then
    log "Seeding /home/liveuser with /etc/skel contents (dotfiles, configs)"
    # Copy hidden + visible top-level entries. `cp -an /etc/skel/. /home/liveuser/`
    # handles dotfiles correctly (the trailing /. is the trick).
    cp -an /etc/skel/. /home/liveuser/ 2>&1 | sed 's/^/  /' || true
    chown -R 1000:1000 /home/liveuser
fi

# ---- Plymouth ------------------------------------------------------------
# Theme descriptor must already be at /usr/share/plymouth/themes/$BRAND/$BRAND.plymouth
# from the overlay. We point plymouthd at it, then regenerate the initramfs.
if [ -f "/usr/share/plymouth/themes/$BRAND/$BRAND.plymouth" ]; then
    mkdir -p /etc/plymouth
    cat >/etc/plymouth/plymouthd.conf <<EOF
[Daemon]
Theme=$BRAND
ShowDelay=0
EOF

    # FAST_BUILD skips the initramfs regen (saves ~10 min across 6 kernels
    # at the cost of an unbranded plymouth splash for the few seconds
    # before SDDM). pre-build.sh writes the marker file when FAST_BUILD=1.
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
# cachyos-calamares-next ships settings.conf at /usr/share/calamares/
# (not /etc/calamares/ like vanilla). Probe both paths so an upstream
# refactor doesn't silently break us. Only flip if our branding.desc
# actually exists, otherwise Calamares would fail to start.
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
# Flip the automatic-install default to btrfs (subvolumes for snapper/
# snap-pac/grub-btrfs). Users can still pick ext4/xfs/f2fs from manual
# partitioning; we only change the default.
for part_conf in /usr/share/calamares/modules/partition.conf /etc/calamares/modules/partition.conf; do
    if [ -f "$part_conf" ]; then
        log "Patching $part_conf → defaultFileSystemType: btrfs"
        sed -i 's|^defaultFileSystemType:.*|defaultFileSystemType: btrfs|' "$part_conf"
        log "  result: $(grep '^defaultFileSystemType:' "$part_conf")"
        break
    fi
done

# ---- Display manager: plasma-login-manager (plasmalogin) ----------------
# plasma-login-manager is upstream KDE's SDDM fork with a new Plasma-native
# greeter that integrates the standard Plasma wallpaper plugin. CachyOS ships
# it as the default DM; we keep it and just override the wallpaper.
#
# Important: per upstream's known bug, config under /etc/plasmalogin.conf.d/
# is silently ignored. The only working config path is /etc/plasmalogin.conf.
log "Writing /etc/plasmalogin.conf (autologin + branded wallpaper)"
# Two keys needed for the wallpaper:
#   [Greeter] WallpaperPluginId=org.kde.image  → "which plugin shows the wallpaper"
#   [Greeter][Wallpaper][org.kde.image][General] Image=  → "which image"
# Missing the first one made plasmalogin try to load an applet with empty
# plugin id → "Error loading Applet: package  does not exist" before the
# greeter rendered.
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
# cachyos-kde-settings ships CachyOS-flavored wallpapers (Sub-Arctic etc.)
# that dilute the brand in System Settings → Wallpaper. Prune anything
# that isn't ours or a stock Breeze wallpaper.
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
# Recolor Papirus's folder icons blue → warm orange. The papirus-folders
# helper is AUR-only, so we vendor v1.14.0 at /usr/local/bin/papirus-folders.
PAPIRUS_COLOR=orange
if [ -d /usr/share/icons/Papirus-Light ] && [ -x /usr/local/bin/papirus-folders ]; then
    log "Recoloring Papirus-Light folders → $PAPIRUS_COLOR (papirus-folders)"
    /usr/local/bin/papirus-folders -t Papirus-Light -C "$PAPIRUS_COLOR" -v \
        || log "WARN: papirus-folders failed"
fi

# Plasma's Discover auto-detects Flatpak when the binary is installed
# (libflatpak is detected at Discover's startup), so no separate
# discover-flatpak-backend package is needed in Plasma 6.
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
# Register Squeak + Loud Noises (installed via overlay-generated/ to
# /usr/share/fonts/posthogos/) so apps can use them by family name.
fc-cache -f /usr/share/fonts 2>/dev/null || true

log "Done."
