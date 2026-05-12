#!/usr/bin/env bash
# Apply the PosthogOS Plasma theme on a user's first Plasma session.
#
# Triggered by /etc/xdg/autostart/posthogos-firstrun.desktop.
#
# Plasma reads /etc/skel/.config/kdeglobals at session bring-up and honors
# ColorScheme + LookAndFeelPackage there, but it doesn't *apply* the LAF
# (wallpaper, plasma style, kwin decoration) from kdeglobals alone — that
# requires the plasma-apply-* triplet.
#
# Idempotent via marker file. Marker only gets written on full success, so
# if any apply command failed we retry on the next session.

# Capture everything for post-mortem in case the script silently fails.
# /tmp survives the session but not reboot, which is what we want here.
exec >>/tmp/posthogos-firstrun.log 2>&1
echo "===== $(date -Iseconds) [pid=$$ uid=$(id -u) user=$(id -un)] ====="

marker="${XDG_CONFIG_HOME:-$HOME/.config}/posthogos-firstrun-applied"
if [ -f "$marker" ]; then
    echo "marker present at $marker — skipping"
    exit 0
fi

# Wait for plasmashell to be alive on the session DBus before driving
# Plasma. apply commands return success but visibly do nothing if called
# before plasmashell has subscribed to the relevant signals.
echo "waiting for plasmashell on session DBus..."
ready=0
for i in $(seq 1 30); do
    if qdbus6 org.kde.plasmashell / >/dev/null 2>&1; then
        echo "  plasmashell ready after ${i}s"
        ready=1
        break
    fi
    sleep 1
done
if [ "$ready" != "1" ]; then
    echo "  plasmashell did not appear in 30s — applying anyway"
fi

apply() {
    echo "+ $*"
    local out rc
    out=$("$@" 2>&1)
    rc=$?
    [ -n "$out" ] && echo "  $out" | sed 's/^/  /'
    echo "  exit=$rc"
    return $rc
}

ok=true
apply plasma-apply-lookandfeel  -a com.posthog.posthogos || ok=false
apply plasma-apply-colorscheme  PosthogosDark            || ok=false
apply plasma-apply-wallpaperimage \
    /usr/share/wallpapers/PosthogosKeyboardGarden/contents/images_dark/3840x2160.png \
    || ok=false

if $ok; then
    mkdir -p "$(dirname "$marker")"
    date -Iseconds > "$marker"
    echo "all applied — marker written to $marker"
else
    echo "one or more apply commands failed — NOT writing marker (will retry next session)"
fi
