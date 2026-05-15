#!/usr/bin/env bash
# Apply the PosthogOS Plasma theme on a user's first Plasma session.
#
# Triggered by /etc/xdg/autostart/posthogos-firstrun.desktop.
#
# Plasma reads /etc/skel/.config/kdeglobals at session bring-up and honors
# ColorScheme + LookAndFeelPackage there, but it doesn't *apply* the LAF
# (wallpaper, plasma style, kwin decoration) from kdeglobals alone. That
# requires the plasma-apply-* triplet plus a kickoff-icon patch.
#
# Idempotent via marker file. Marker only gets written on full success, so
# if any apply command failed we retry on the next session.

# Capture everything for post-mortem in case the script silently fails.
exec >>/tmp/posthogos-firstrun.log 2>&1
echo "===== $(date -Iseconds) [pid=$$ uid=$(id -u) user=$(id -un)] ====="

marker="${XDG_CONFIG_HOME:-$HOME/.config}/posthogos-firstrun-applied"
if [ -f "$marker" ]; then
    echo "marker present at $marker, skipping"
    exit 0
fi

# Wait for plasmashell on the session DBus; apply commands silently no-op
# if called before plasmashell subscribes. Short 10s timeout because the
# rescue service handles the autostart-fires-too-early race at the system
# level (it polls for kwin and re-invokes us with verified-good env).
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
    echo "  plasmashell did not appear in 10s; applying anyway (rescue service will retry if needed)"
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
# Wallpaper PACKAGE directory, not a specific PNG: lets Plasma pick the
# right size per-display and shows the package's metadata.json Name in
# System Settings → Wallpaper (a specific PNG shows up as "3840x2160").
wallpaper=/usr/share/wallpapers/PosthogosKeyboardGarden/

apply plasma-apply-lookandfeel  -a com.posthog.posthogos || ok=false
apply plasma-apply-colorscheme  PosthogosLight           || ok=false
apply plasma-apply-wallpaperimage "$wallpaper"           || ok=false

# Belt-and-suspenders push via plasmashell's evaluateScript interface.
# plasma-apply-wallpaperimage returns 0 as long as it could emit the DBus
# call; if plasmashell wasn't subscribed yet, the wallpaper stays default.
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
        || echo "  (evaluateScript failed; relying on plasma-apply-wallpaperimage above)"
fi

# Verify wallpaper actually landed in plasma's appletsrc. If our path
# isn't there after both apply paths, plasmashell wasn't ready to consume
# the change. Fail loudly so the marker DOESN'T get written and the
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

# Taskbar pins, left to right. posthog-code.desktop is conditional (only
# present if POSTHOG_CODE_APPIMAGE was staged at build time); Plasma
# silently drops unknown entries. Calamares isn't pinned: the welcome
# window's "Install to disk" tile already surfaces it.
taskbar_launchers="applications:firefox.desktop,applications:com.mitchellh.ghostty.desktop,applications:org.kde.dolphin.desktop,applications:posthog-code.desktop,applications:posthogos-welcome.desktop"

# Kickoff "Favorites" tab (separator-only different format).
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
        # Ask plasmashell to refresh its config. NEVER kill+relaunch as a
        # fallback: kquitapp6 followed by `kstart plasmashell &` detaches
        # the new process from our script's session env, and in QEMU TCG
        # sessions the relaunched plasmashell can't reattach to the
        # display, leaving the user staring at a black screen post-login.
        # If the DBus call fails, we accept the appletsrc edits landing on
        # next login instead of forcing them now.
        echo "  asking plasmashell to refresh config"
        qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.refreshCurrentShell 2>/dev/null \
            || echo "  refreshCurrentShell failed; edits will apply on next login"
    else
        echo "  no kickoff or taskbar applets found (appletsrc layout may differ)"
        ok=false
    fi
else
    echo "  appletsrc not present yet (plasmashell hasn't written it)"
    ok=false
fi

if $ok; then
    mkdir -p "$(dirname "$marker")"
    date -Iseconds > "$marker"
    echo "all applied; marker written to $marker"
else
    echo "one or more steps failed; NOT writing marker (will retry next session)"
fi
