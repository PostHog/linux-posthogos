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
#
# Short timeout here (10s) because posthogos-firstrun-rescue.service is the
# real safety net for the autostart-fires-too-early race: it polls for kwin
# at the system level, harvests session env from /proc, and re-invokes us
# with verified-good env. Spending 30s here on every login just to handle
# the rare race isn't worth it.
echo "waiting for plasmashell on session DBus..."
ready=0
for i in $(seq 1 10); do
    if qdbus6 org.kde.plasmashell / >/dev/null 2>&1; then
        echo "  plasmashell ready after ${i}s"
        ready=1
        break
    fi
    sleep 1
done
if [ "$ready" != "1" ]; then
    echo "  plasmashell did not appear in 10s — applying anyway (rescue service will retry if needed)"
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
# Point at the wallpaper PACKAGE DIRECTORY, not a specific PNG inside it.
# plasma-apply-wallpaperimage and Plasma's appletsrc both accept either,
# but with a specific PNG, Plasma renders the entry in System Settings →
# Wallpaper as "3840x2160" (just the filename) rather than "Keyboard
# Garden" — looks like an unbranded mystery wallpaper. With the package
# directory, Plasma picks the right size per-display AND shows the
# package's metadata.json Name in the UI.
wallpaper=/usr/share/wallpapers/PosthogosKeyboardGarden/

apply plasma-apply-lookandfeel  -a com.posthog.posthogos || ok=false
apply plasma-apply-colorscheme  PosthogosLight           || ok=false
apply plasma-apply-wallpaperimage "$wallpaper"           || ok=false

# Belt-and-suspenders wallpaper push via plasmashell's JS scripting API.
# plasma-apply-wallpaperimage exit 0 doesn't guarantee plasmashell actually
# consumed the change (the apply binary returns success as long as it can
# emit the DBus call; if plasmashell wasn't subscribed when the call hit,
# the wallpaper stays at default). evaluateScript drives plasmashell
# directly via its public PlasmaShell scripting interface — same path
# System Settings → Wallpaper uses internally.
if [ -d "$wallpaper" ] && command -v qdbus6 >/dev/null; then
    plasma_script=$(cat <<EOF
        var img = "${wallpaper}";
        for (const d of desktops()) {
            d.wallpaperPlugin = "org.kde.image";
            d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
            d.writeConfig("Image", img);
            d.writeConfig("PreviewImage", img);
        }
EOF
    )
    apply qdbus6 org.kde.plasmashell /PlasmaShell \
        org.kde.PlasmaShell.evaluateScript "$plasma_script" \
        || echo "  (evaluateScript failed — relying on plasma-apply-wallpaperimage above)"
fi

# Verify wallpaper actually landed in plasma's appletsrc. If our path
# isn't there after both apply paths, plasmashell wasn't ready to consume
# the change — fail loudly so the marker DOESN'T get written and the
# rescue service picks us up on its next cycle.
sleep 1   # let plasmashell flush its config write
appletsrc="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
if [ -f "$appletsrc" ] && ! grep -qF "PosthogosKeyboardGarden" "$appletsrc"; then
    echo "  WARN: wallpaper apply silently no-op'd (path not in $appletsrc)"
    ok=false
fi

# ---- Plasma panel customizations ----------------------------------------
# Patch plasma-org.kde.plasma.desktop-appletsrc to:
#   1. set the Kickoff start-button icon to the PostHog logomark
#   2. set Kickoff's "Favorites" tab to our preferred app list
#   3. set the taskbar (icontasks) launchers to our preferred pinned apps
#
# We don't replace the whole appletsrc (would fight CachyOS's layout and
# break on Plasma upgrades). We patch only specific keys on the applets
# that match known plugin IDs.

# Pinned launchers for the taskbar (icontasks). Order matters — left to
# right. ":" entries are placeholders for the app's .desktop file in
# /usr/share/applications/. posthog-code.desktop only exists if the
# AppImage was staged at build time (POSTHOG_CODE_APPIMAGE in bin/build);
# Plasma silently drops unknown launcher entries, so listing it here is
# a no-op when absent.
#
# Calamares is intentionally NOT pinned to the taskbar — the live ISO's
# Welcome app (posthogos-welcome) has a prominent "Install to disk" tile
# that launches it, which is enough surface area without cluttering the
# bar with an installer that's only relevant for the first few minutes.
taskbar_launchers="applications:firefox.desktop,applications:com.mitchellh.ghostty.desktop,applications:org.kde.dolphin.desktop,applications:posthog-code.desktop,applications:posthogos-welcome.desktop"

# Kickoff "Favorites" tab — separator-only different format.
kickoff_favorites="applications:firefox.desktop,applications:com.mitchellh.ghostty.desktop,applications:org.kde.dolphin.desktop,applications:posthog-code.desktop,applications:systemsettings.desktop,applications:posthogos-welcome.desktop"

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
