#!/usr/bin/env bash
# Apply the PosthogOS Plasma theme on a user's first Plasma session.
#
# Triggered by /etc/xdg/autostart/posthogos-firstrun.desktop. Idempotent:
# leaves a marker so subsequent logins skip the work.
#
# Why this exists: Plasma reads /etc/skel/.config/kdeglobals as the source
# of truth for new accounts, but doesn't always *apply* the look-and-feel
# package on first run — wallpaper/colour-scheme stay at upstream defaults
# until the user explicitly switches. plasma-apply-* forces application.

set -e

marker="${XDG_CONFIG_HOME:-$HOME/.config}/posthogos-firstrun-applied"
[ -f "$marker" ] && exit 0

# Give Plasma a moment to finish session bring-up before we drive it.
sleep 3

apply() {
    "$@" >/dev/null 2>&1 || true
}

apply plasma-apply-lookandfeel  -a com.posthog.posthogos
apply plasma-apply-colorscheme  PosthogosDark
apply plasma-apply-wallpaperimage \
    /usr/share/wallpapers/PosthogosKeyboardGarden/contents/images_dark/3840x2160.png

mkdir -p "$(dirname "$marker")"
date -Iseconds > "$marker"
