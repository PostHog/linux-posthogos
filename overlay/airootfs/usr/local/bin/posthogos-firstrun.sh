#!/usr/bin/env bash
# Apply the PosthogOS Plasma theme on a user's first Plasma session.
#
# Triggered by /etc/xdg/autostart/posthogos-firstrun.desktop.
#
# Plasma reads /etc/skel/.config/kdeglobals at session bring-up and honors
# ColorScheme + LookAndFeelPackage there, but it doesn't *apply* the LAF
# (wallpaper, plasma style, kwin decoration) from kdeglobals alone — that
# requires the plasma-apply-* triplet plus a kickoff-icon patch.
#
# Idempotent via marker file. Marker only gets written on full success, so
# if any apply command failed we retry on the next session.

# Capture everything for post-mortem in case the script silently fails.
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
    [ -n "$out" ] && echo "$out" | sed 's/^/  /'
    echo "  exit=$rc"
    return $rc
}

ok=true
apply plasma-apply-lookandfeel  -a com.posthog.posthogos || ok=false
apply plasma-apply-colorscheme  PosthogosLight           || ok=false
apply plasma-apply-wallpaperimage \
    /usr/share/wallpapers/PosthogosKeyboardGarden/contents/images/3840x2160.png \
    || ok=false

# ---- Swap Kickoff / application launcher icon to PostHog logo ----------
# Plasma's start-button widgets read an "icon" key under their applet's
# [Configuration][General] group. The applet ID varies per session, so we
# scan plasma-org.kde.plasma.desktop-appletsrc for any applet whose
# plugin is a known launcher and patch its icon to "posthogos" (the
# hicolor system icon we ship at /usr/share/icons/hicolor/*/apps/posthogos.png).
appletsrc="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
echo "+ patch kickoff icon in $appletsrc"
if [ -f "$appletsrc" ]; then
    patched=0
    # Find all "[Containments][N][Applets][M]" headers, then the next line
    # to see if plugin matches a launcher we want to skin. Use awk to emit
    # "N M" pairs, then feed kwriteconfig6.
    while read -r cont applet; do
        kwriteconfig6 --file "$appletsrc" \
            --group "Containments" --group "$cont" \
            --group "Applets" --group "$applet" \
            --group "Configuration" --group "General" \
            --key icon posthogos
        patched=$((patched + 1))
        echo "  patched Containments/$cont/Applets/$applet → icon=posthogos"
    done < <(awk '
        /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ {
            match($0, /\[Containments\]\[([0-9]+)\]\[Applets\]\[([0-9]+)\]/, m)
            cur_cont=m[1]; cur_applet=m[2]
            in_section=1; next
        }
        /^\[/ { in_section=0 }
        in_section && /^plugin=org\.kde\.plasma\.(kickoff|kicker|kickerdash|applicationlauncher)$/ {
            print cur_cont, cur_applet
            in_section=0
        }
    ' "$appletsrc")
    if [ "$patched" -gt 0 ]; then
        echo "  asking plasmashell to reload"
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.refreshCurrentShell 2>/dev/null \
            || kquitapp6 plasmashell 2>/dev/null
        kstart plasmashell >/dev/null 2>&1 &
    else
        echo "  no launcher applets found — appletsrc layout may differ"
        ok=false
    fi
else
    echo "  appletsrc not present yet — plasmashell hasn't written it"
    ok=false
fi

if $ok; then
    mkdir -p "$(dirname "$marker")"
    date -Iseconds > "$marker"
    echo "all applied — marker written to $marker"
else
    echo "one or more steps failed — NOT writing marker (will retry next session)"
fi
