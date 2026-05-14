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

# ---- OS identity ---------------------------------------------------------
# These files are owned by upstream packages (filesystem, lsb-release), so
# we can't pre-stage them in airootfs/etc/ — pacstrap refuses to overwrite.
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

  Welcome to PosthogOS — a CachyOS-based spin with PostHog branding.

  Live environment ready. Pick "Install PosthogOS" from the desktop to
  install to disk, or explore the live session.

  Source: https://github.com/posthog/linux-posthogos
  Issues: https://github.com/posthog/linux-posthogos/issues

EOF

# ---- liveuser home + XDG base dirs --------------------------------------
# Plasma session crashes with "Error loading Applet: package  does not
# exist" when ksycoca (KDE's service cache) can't write ~/.cache, which
# happens if liveuser doesn't own /home/liveuser/.cache or the dir
# doesn't exist yet. Chmod alone on the home root isn't enough — the
# subdirs must exist with liveuser:liveuser ownership *before* first
# login. Apps creating .cache lazily fails when the home tree was
# populated by root during pacstrap post-install hooks.
# Don't gate on `id liveuser` — nsswitch may not be fully primed inside
# the pacstrap chroot, causing id to fail even though /etc/passwd has
# liveuser. Use the UID/GID directly. This is also belt-and-suspenders for
# the systemd-tmpfiles entry at /etc/tmpfiles.d/posthogos-liveuser.conf
# (which is the actual load-bearing fix; runs at boot regardless).
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

# Belt-and-suspenders: ensure every shell script we ship in /usr/local/bin/
# is executable. The Write tool resets file mode to 0644 when overwriting,
# and rsync -a faithfully preserves the bad mode into the squashfs — at
# which point autostart entries pointing at non-executable scripts fail
# silently with "Permission denied".
#
# Same story for the PostHog Code AppImage at /opt/posthog-code/ — even
# though build-assets.sh chmod 755's it on the host, Docker Desktop's
# bind-mount perm propagation on macOS is unreliable, so the squashfs
# can end up with 0644 → Plasma's launcher fails with "missing executable
# permissions". chmod in the chroot guarantees real Linux perms.
if [ -d /usr/local/bin ]; then
    # Everything we ship under /usr/local/bin/posthogos-* is intended to
    # be executable (helpers + launchers), so chmod the whole namespace.
    chmod +x /usr/local/bin/posthogos-* 2>/dev/null || true
    chmod +x /usr/local/bin/papirus-folders 2>/dev/null || true
fi
if [ -d /opt/posthog-code ]; then
    chmod +x /opt/posthog-code/*.AppImage 2>/dev/null || true
fi

# ---- Compile the welcome launcher ---------------------------------------
# Tiny C++ shim that calls QGuiApplication::setDesktopFileName("posthogos-
# welcome") + setWindowIcon() before loading welcome.qml. Without this, the
# qml6 binary that previously ran the QML sets app_id to "qml" and Plasma
# can't match the running window to /usr/share/applications/posthogos-
# welcome.desktop → generic Qt icon in titlebar + taskbar.
#
# Compiled here (rather than pre-built on the host) so the binary is
# linked against the SAME Qt6 ABI it'll run against — no minor-version-
# mismatch risk between host container and final airootfs.
launcher_src=/usr/src/posthogos-welcome-launcher.cpp
if [ -f "$launcher_src" ] && command -v g++ >/dev/null && command -v pkg-config >/dev/null; then
    log "Compiling welcome launcher"
    if g++ -O2 -fPIC -o /usr/local/bin/posthogos-welcome-launcher \
            "$launcher_src" \
            $(pkg-config --cflags --libs Qt6Core Qt6Gui Qt6Qml) 2>&1 | sed 's/^/  /'; then
        chmod +x /usr/local/bin/posthogos-welcome-launcher
        rm -f "$launcher_src"
        log "  built /usr/local/bin/posthogos-welcome-launcher ($(stat -c%s /usr/local/bin/posthogos-welcome-launcher) bytes)"
    else
        log "  WARN: launcher compile failed — bash wrapper will fall back to qml6 (icon will be generic)"
    fi
fi

# ---- Suppress CachyOS Hello popup ---------------------------------------
# cachyos-hello pops up a welcome window on every login (toggle is in the
# app itself but defaults to on). Override its autostart by dropping a
# user-level .desktop with Hidden=true — XDG autostart spec gives user-level
# precedence over /etc/xdg.
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
EOF

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

# Konsole: select the PosthogOS profile (shipped at /usr/share/konsole/
# PosthogOS.profile, which references the PosthogOS color scheme also
# shipped there). Setting DefaultProfile in konsolerc makes new windows
# use it without users touching anything.
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
#
# Important: cachyos-calamares-next ships settings.conf at
# /usr/share/calamares/settings.conf (NOT /etc/calamares/settings.conf like
# vanilla Calamares). Both candidate paths checked so a future upstream
# refactor doesn't silently break us again — we patch whichever exists.
cal_settings=""
for candidate in /usr/share/calamares/settings.conf /etc/calamares/settings.conf; do
    [ -f "$candidate" ] && cal_settings="$candidate" && break
done
if [ -n "$cal_settings" ] && [ -f "/usr/share/calamares/branding/$BRAND/branding.desc" ]; then
    log "Patching $cal_settings branding: $BRAND"
    sed -i "s/^branding:.*/branding: $BRAND/" "$cal_settings"
    log "  result: $(grep '^branding:' "$cal_settings")"
else
    log "Calamares branding '$BRAND' not present at any known settings.conf path — leaving CachyOS default"
fi

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

# Our SDDM theme files (overlay/airootfs/usr/share/sddm/themes/posthogos/)
# stay shipped as a fallback for anyone who later switches to SDDM via
# `pacman -S sddm && systemctl enable sddm`. The chroot hook used to flip
# the active DM here; that's now plasma-login-manager's job and the user
# chose not to fight upstream.

# ---- Papirus folder color ------------------------------------------------
# Recolor Papirus's folder icons (default blue → warm orange) using the
# upstream papirus-folders helper vendored at /usr/local/bin/papirus-folders
# (overlay/airootfs/usr/local/bin/papirus-folders, pinned to v1.14.0). It's
# AUR-only as a package so we can't pacstrap it; vendoring the script avoids
# both the AUR dep and reimplementing the symlink-repoint logic ourselves.
PAPIRUS_COLOR=orange
if [ -d /usr/share/icons/Papirus-Light ] && [ -x /usr/local/bin/papirus-folders ]; then
    log "Recoloring Papirus-Light folders → $PAPIRUS_COLOR (papirus-folders)"
    /usr/local/bin/papirus-folders -t Papirus-Light -C "$PAPIRUS_COLOR" -v \
        || log "WARN: papirus-folders failed"
fi

# ---- Docker engine setup -------------------------------------------------
# `docker` + `docker-compose` are pacstrap'd via the package list (see
# scripts/pre-build.sh). Two more steps to make Docker actually usable
# without manual setup on first boot:
#
#   1. Enable docker.service so the daemon starts at boot. The package
#      ships the unit but doesn't enable it by default — leaving it off
#      means every fresh boot needs `sudo systemctl start docker` before
#      `docker ps` works, which is a paper cut nobody wants.
#
#   2. Add liveuser to the `docker` group so they can run `docker` without
#      sudo. (Post-install: the same will need to happen for whatever user
#      Calamares creates — Calamares has no hook for this, so we'd need a
#      first-login service if we want it automatic. For now, live-only.)
if command -v systemctl >/dev/null && [ -f /usr/lib/systemd/system/docker.service ]; then
    log "Enabling docker.service"
    systemctl enable docker.service 2>&1 | sed 's/^/  /' || log "WARN: docker.service enable failed"
fi

# Use grep on /etc/passwd directly rather than `id liveuser` — nsswitch
# inside the pacstrap chroot doesn't always resolve users via id (same
# reason the home-provisioning section above uses uid 1000 numerically).
# gpasswd reads /etc/group + /etc/passwd as files, so as long as both
# entries exist, the add works regardless of nsswitch state.
if getent group docker >/dev/null && grep -q '^liveuser:' /etc/passwd; then
    log "Adding liveuser to docker group"
    gpasswd -a liveuser docker 2>&1 | sed 's/^/  /' || log "WARN: gpasswd failed"
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
