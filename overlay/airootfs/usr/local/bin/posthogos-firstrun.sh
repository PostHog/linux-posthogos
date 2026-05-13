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

# ---- Plasma panel customizations ----------------------------------------
# Patch plasma-org.kde.plasma.desktop-appletsrc to:
#   1. set the Kickoff start-button icon to the PostHog logomark
#   2. set Kickoff's "Favorites" tab to our preferred app list
#   3. set the taskbar (icontasks) launchers to our preferred pinned apps
#
# We don't replace the whole appletsrc (would fight CachyOS's layout and
# break on Plasma upgrades). We patch only specific keys on the applets
# that match known plugin IDs.

# Detect live-ISO vs installed system. If live, include Calamares in the
# pinned launchers so users can install with one click.
is_live=0
[ -d /run/archiso ] && is_live=1

# Pinned launchers for the taskbar (icontasks). Order matters — left to
# right. ":" entries are placeholders for the app's .desktop file in
# /usr/share/applications/.
taskbar_launchers="applications:firefox.desktop,applications:org.kde.konsole.desktop,applications:org.kde.dolphin.desktop,applications:posthogos-welcome.desktop"
if [ "$is_live" = "1" ]; then
    taskbar_launchers="$taskbar_launchers,applications:io.calamares.calamares.desktop"
fi

# Kickoff "Favorites" tab — separator-only different format.
kickoff_favorites="applications:firefox.desktop,applications:org.kde.konsole.desktop,applications:org.kde.dolphin.desktop,applications:systemsettings.desktop,applications:posthogos-welcome.desktop"

appletsrc="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
echo "+ patching $appletsrc"
if [ -f "$appletsrc" ]; then
    # Read every [Containments][N][Applets][M] section and emit
    # "$cont $applet $plugin" rows so we can dispatch by plugin type.
    applets=$(awk '
        /^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ {
            match($0, /\[Containments\]\[([0-9]+)\]\[Applets\]\[([0-9]+)\]/, m)
            cur_cont=m[1]; cur_applet=m[2]
            in_section=1; next
        }
        /^\[/ { in_section=0 }
        in_section && /^plugin=/ {
            sub(/^plugin=/, "", $0)
            print cur_cont, cur_applet, $0
            in_section=0
        }
    ' "$appletsrc")

    patched_kickoff=0
    patched_tasks=0
    while read -r cont applet plugin; do
        [ -z "$plugin" ] && continue
        case "$plugin" in
            org.kde.plasma.kickoff|org.kde.plasma.kicker|org.kde.plasma.kickerdash|org.kde.plasma.applicationlauncher)
                # Kickoff icon → PostHog logomark
                kwriteconfig6 --file "$appletsrc" \
                    --group "Containments" --group "$cont" \
                    --group "Applets" --group "$applet" \
                    --group "Configuration" --group "General" \
                    --key icon posthogos
                # Kickoff Favorites tab → our app list
                kwriteconfig6 --file "$appletsrc" \
                    --group "Containments" --group "$cont" \
                    --group "Applets" --group "$applet" \
                    --group "Configuration" --group "General" \
                    --key favorites "$kickoff_favorites"
                # Tell newer kickoff (KAStats) that favorites have been
                # ported, so it stops asking on first launch.
                kwriteconfig6 --file "$appletsrc" \
                    --group "Containments" --group "$cont" \
                    --group "Applets" --group "$applet" \
                    --group "Configuration" --group "General" \
                    --key favoritesPortedToKAstats true
                patched_kickoff=$((patched_kickoff + 1))
                echo "  Kickoff[$cont/$applet]: icon + favorites set"
                ;;
            org.kde.plasma.icontasks|org.kde.plasma.taskmanager|org.kde.plasma.expandingiconspacer)
                # Taskbar pinned launchers
                kwriteconfig6 --file "$appletsrc" \
                    --group "Containments" --group "$cont" \
                    --group "Applets" --group "$applet" \
                    --group "Configuration" --group "General" \
                    --key launchers "$taskbar_launchers"
                patched_tasks=$((patched_tasks + 1))
                echo "  Taskbar[$cont/$applet]: launchers set"
                ;;
        esac
    done <<<"$applets"

    if [ "$patched_kickoff" -gt 0 ] || [ "$patched_tasks" -gt 0 ]; then
        echo "  patched $patched_kickoff kickoff + $patched_tasks taskbar applet(s)"
        echo "  asking plasmashell to reload"
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.refreshCurrentShell 2>/dev/null \
            || { kquitapp6 plasmashell 2>/dev/null; kstart plasmashell >/dev/null 2>&1 & }
    else
        echo "  no kickoff or taskbar applets found — appletsrc layout may differ"
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
