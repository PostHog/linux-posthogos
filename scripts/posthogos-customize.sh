#!/usr/bin/env bash
# Runs inside the airootfs chroot, after pacstrap, before squashfs assembly.
#
# Two halves:
#   1. Shared system tweaks — delegated to `posthogos-apply-common` (shipped
#      by posthogos-scripts, so it's already pacstrapped here). The exact
#      same script runs on a Calamares-installed target via the postinstall
#      hook, keeping live == installed.
#   2. Live-only logic below — liveuser provisioning/identity/autologin,
#      build-time perm fixups, and Calamares config patches (Calamares only
#      ever runs in the live session, so its config belongs here, not in
#      apply-common).
#
# Idempotent: safe to re-run on retry.

set -euo pipefail

log() { printf '[posthogos-customize] %s\n' "$*"; }

BRAND="posthogos"

# ---- Shared system tweaks ------------------------------------------------
# os-release, [posthogos] repo, /etc/skel Plasma+GTK defaults, plymouth,
# wallpaper pruning, papirus recolor, flathub, caches, … See the script for
# the full list. Writes /etc/skel/* that the liveuser seeding below depends
# on, so it must run first.
log "Applying shared system tweaks (posthogos-apply-common)"
/usr/local/bin/posthogos-apply-common

# ---- Hostname (live only) ------------------------------------------------
# The installed target gets its hostname from Calamares' users module
# (template patched below), so this is the live ISO's hostname only.
log "Writing /etc/hostname"
echo "posthogos" > /etc/hostname

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

# Re-chmod in the chroot: Docker Desktop's bind-mount perm propagation on
# macOS is unreliable, so the +x bit on overlay scripts gets lost.
if [ -d /usr/local/bin ]; then
    chmod +x /usr/local/bin/* 2>/dev/null || true
fi
if [ -d /opt/posthog-code ]; then
    chmod +x /opt/posthog-code/*.AppImage 2>/dev/null || true
fi

# ---- Suppress CachyOS Hello popup for the live user ---------------------
# apply-common handled /etc/skel; seed the existing liveuser home too
# (skel is consulted at user-creation only, and liveuser predates it).
if [ -d /home/liveuser ]; then
    log "Suppressing cachyos-hello autostart for liveuser"
    install -d -o 1000 -g 1000 -m 0755 /home/liveuser/.config/autostart
    cat >/home/liveuser/.config/autostart/cachyos-hello.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=CachyOS Hello
Hidden=true
EOF
    chown 1000:1000 /home/liveuser/.config/autostart/cachyos-hello.desktop
fi

# Konsole branded profile for the existing live user (apply-common wrote
# the /etc/skel copy).
if [ -d /home/liveuser ] && [ -f /etc/skel/.config/konsolerc ]; then
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

# ---- Display manager: live autologin (plasma-login-manager) -------------
# apply-common already wrote the branded greeter config (/etc/plasmalogin.conf).
# Layer the live ISO's passwordless autologin on top. Installed systems skip
# this — their real user / autologin choice comes from Calamares' users +
# displaymanager modules.
if [ -f /etc/plasmalogin.conf ] && ! grep -q '^\[Autologin\]' /etc/plasmalogin.conf; then
    log "Adding live autologin (liveuser) to /etc/plasmalogin.conf"
    cat >>/etc/plasmalogin.conf <<'EOF'

[Autologin]
User=liveuser
Session=plasma.desktop
Relogin=false
EOF
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

# ---- Calamares: install PosthogOS onto the target -----------------------
# The active settings.conf does a fresh online pacstrap, so nothing
# PosthogOS reaches the target unless we wire it in. Register a shellprocess
# instance that runs our postinstall hook (installs the posthogos meta +
# runs posthogos-apply-common in the target chroot), and insert it into the
# exec sequence right before the generic `shellprocess` cleanup step — so
# the /etc/skel defaults it writes get backfilled into the new user's home
# by that step's `cp -rf /etc/skel/. /home/$USER/.`.
if [ -n "${cal_settings:-}" ] && [ -f /etc/calamares/modules/posthogos-postinstall.conf ]; then
    # macOS Docker bind-mounts drop the +x bit off overlay files; restore it
    # so Calamares can exec the hook.
    [ -f /etc/calamares/scripts/posthogos-postinstall ] && \
        chmod +x /etc/calamares/scripts/posthogos-postinstall
    if ! grep -q 'posthogos_postinstall' "$cal_settings"; then
        log "Registering posthogos_postinstall shellprocess in $cal_settings"
        # Declare the instance right after the `instances:` line (awk, not a
        # multi-line `sed a\` — the latter's line-continuation rules differ
        # across sed builds). cp back into place to preserve the file's
        # package-owned inode + mode.
        tmp=$(mktemp)
        awk '
            { print }
            /^instances:/ && !done {
                print ""
                print "- id:       posthogos_postinstall"
                print "  module:   shellprocess"
                print "  config:   posthogos-postinstall.conf"
                done = 1
            }
        ' "$cal_settings" > "$tmp" && cp "$tmp" "$cal_settings"
        rm -f "$tmp"
        # Insert into the exec sequence just before the bare `- shellprocess`
        # (the `$` anchor leaves the `@`-suffixed instances untouched).
        sed -i 's/^\(\s*\)- shellprocess$/\1- shellprocess@posthogos_postinstall\n\1- shellprocess/' "$cal_settings"
        log "  exec sequence now: $(grep -n 'shellprocess' "$cal_settings" | tr '\n' ' ')"
    else
        log "posthogos_postinstall already registered in $cal_settings"
    fi
else
    log "posthogos-postinstall.conf absent; skipping installer wiring (target will be vanilla CachyOS)"
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

log "Done."
