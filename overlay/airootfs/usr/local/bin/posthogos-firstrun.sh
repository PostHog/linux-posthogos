#!/usr/bin/env bash
# Apply the PosthogOS theme on a user's first desktop session.
#
# Triggered by /etc/xdg/autostart/posthogos-firstrun.desktop (which has no
# OnlyShowIn, so it fires under every desktop).
#
# Dispatches on the running desktop environment:
#   - KDE Plasma : the plasma-apply-* triplet + a kickoff/taskbar patch
#                  (Plasma reads ColorScheme/LookAndFeelPackage from
#                  kdeglobals but doesn't *apply* the LAF from it alone).
#   - GNOME      : gsettings (wallpaper, dark/light, accent, icon theme,
#                  fonts, dock favorites). Tier-1 "PosthogOS flavor" — no
#                  custom Shell/GTK theme; just the brand via gsettings keys.
#   - Cinnamon   : gsettings org.cinnamon.* (wallpaper, icon theme, font).
#   - XFCE       : xfconf-query (wallpaper, icon theme, font).
#   - anything else: a desktop notification explaining which desktops are
#                  supported; no changes made.
#
# Idempotent via marker file. Marker only gets written on full success, so
# if any apply step failed we retry on the next session.

# Capture everything for post-mortem in case the script silently fails.
exec >>/tmp/posthogos-firstrun.log 2>&1
echo "===== $(date -Iseconds) [pid=$$ uid=$(id -u) user=$(id -un)] ====="

marker="${XDG_CONFIG_HOME:-$HOME/.config}/posthogos-firstrun-applied"
if [ -f "$marker" ]; then
    echo "marker present at $marker, skipping"
    exit 0
fi

# Wallpaper PACKAGE directory (Plasma) + concrete PNGs (GNOME wants a file).
wallpaper=/usr/share/wallpapers/PosthogosKeyboardGarden/
wallpaper_light="${wallpaper}contents/images/3840x2160.png"
wallpaper_dark="${wallpaper}contents/images_dark/3840x2160.png"

ok=true

apply() {
    echo "+ $*"
    local out rc
    out=$("$@" 2>&1)
    rc=$?
    [ -n "$out" ] && echo "$out" | sed 's/^/  /'
    echo "  exit=$rc"
    return $rc
}

notify() {
    # Best-effort desktop toast; never fatal.
    command -v notify-send >/dev/null 2>&1 \
        && notify-send -a PosthogOS "$1" "$2" 2>/dev/null || true
}

# Which desktop are we in? Lowercased match over the standard env vars.
detect_desktop() {
    local d
    d=$(printf '%s:%s' "${XDG_CURRENT_DESKTOP:-}" "${DESKTOP_SESSION:-}" \
        | tr '[:upper:]' '[:lower:]')
    case "$d" in
        *kde*|*plasma*) echo plasma ;;
        *cinnamon*)     echo cinnamon ;;   # "X-Cinnamon"
        *xfce*)         echo xfce ;;
        *gnome*|*budgie*) echo gnome ;;     # "ubuntu:GNOME", "Budgie:GNOME"
        *)              echo other ;;
    esac
}

# ───────────────────────── GNOME ─────────────────────────────────────────
# Set a key only when its schema+key exist and are writable, so we degrade
# gracefully across GNOME versions (e.g. accent-color is GNOME 47+).
gset() {
    local schema="$1" key="$2"; shift 2
    if gsettings writable "$schema" "$key" >/dev/null 2>&1; then
        apply gsettings set "$schema" "$key" "$@" || ok=false
    else
        echo "  skip $schema $key (schema/key not present)"
    fi
}

# Resolve the first installed .desktop id from a candidate list (handles
# snap/distro id drift, e.g. firefox.desktop vs firefox_firefox.desktop).
resolve_desktop_id() {
    local id dir
    for id in "$@"; do
        for dir in /usr/share/applications "$HOME/.local/share/applications" \
                   /var/lib/snapd/desktop/applications; do
            [ -f "$dir/$id" ] && { echo "$id"; return 0; }
        done
    done
    return 1
}

apply_gnome() {
    echo "desktop=GNOME → applying via gsettings"
    command -v gsettings >/dev/null 2>&1 || { echo "  gsettings missing"; ok=false; return; }

    # Light scheme to match the Plasma default (PosthogosLight).
    gset org.gnome.desktop.interface color-scheme 'prefer-light'
    # Brand orange accent (GNOME 47+; enum, closest to #F54E00).
    gset org.gnome.desktop.interface accent-color 'orange'
    # Icon theme (inherits Papirus for anything we don't override).
    gset org.gnome.desktop.interface icon-theme 'PosthogOS'

    # UI/document font → Inter when present (a Recommends, may be absent).
    if fc-list 2>/dev/null | grep -qi 'inter'; then
        gset org.gnome.desktop.interface font-name 'Inter 10'
        gset org.gnome.desktop.interface document-font-name 'Inter 10'
    else
        echo "  Inter font not installed; leaving font-name default"
    fi

    # Wallpaper (light + dark) + lock screen.
    if [ -f "$wallpaper_light" ]; then
        local dark="$wallpaper_dark"; [ -f "$dark" ] || dark="$wallpaper_light"
        gset org.gnome.desktop.background picture-uri      "file://$wallpaper_light"
        gset org.gnome.desktop.background picture-uri-dark "file://$dark"
        gset org.gnome.desktop.background picture-options  'zoom'
        gset org.gnome.desktop.screensaver picture-uri     "file://$wallpaper_light"
    else
        echo "  wallpaper missing: $wallpaper_light"; ok=false
    fi

    # Dock / overview favorites (GNOME Shell only). Build from apps that
    # actually exist so we don't pin dead launchers.
    if gsettings writable org.gnome.shell favorite-apps >/dev/null 2>&1; then
        local favs=() id
        for cands in \
            "posthogos-welcome.desktop" \
            "firefox.desktop firefox_firefox.desktop" \
            "com.mitchellh.ghostty.desktop" \
            "org.gnome.Nautilus.desktop nautilus.desktop" \
            "org.gnome.Console.desktop org.gnome.Terminal.desktop" \
            "posthog-code.desktop" \
            "org.gnome.Settings.desktop gnome-control-center.desktop"; do
            if id=$(resolve_desktop_id $cands); then favs+=("'$id'"); fi
        done
        if [ ${#favs[@]} -gt 0 ]; then
            local list; list=$(IFS=,; echo "${favs[*]}")
            gset org.gnome.shell favorite-apps "[$list]"
        fi
    else
        echo "  org.gnome.shell favorite-apps not writable; skipping dock pins"
    fi

    # gsettings changes apply live — no logout needed on GNOME.
}

# ───────────────────────── Cinnamon ──────────────────────────────────────
# Cinnamon (Linux Mint) forks the GNOME schemas under org.cinnamon.*.
# Tier-1: wallpaper, icon theme, font. No custom Cinnamon/GTK theme.
apply_cinnamon() {
    echo "desktop=Cinnamon → applying via gsettings org.cinnamon.*"
    command -v gsettings >/dev/null 2>&1 || { echo "  gsettings missing"; ok=false; return; }

    gset org.cinnamon.desktop.interface icon-theme 'PosthogOS'
    if fc-list 2>/dev/null | grep -qi 'inter'; then
        gset org.cinnamon.desktop.interface font-name 'Inter 10'
    fi
    if [ -f "$wallpaper_light" ]; then
        gset org.cinnamon.desktop.background picture-uri     "file://$wallpaper_light"
        gset org.cinnamon.desktop.background picture-options 'zoom'
    else
        echo "  wallpaper missing: $wallpaper_light"; ok=false
    fi
}

# ───────────────────────── XFCE ──────────────────────────────────────────
# XFCE uses xfconf (not gsettings). Tier-1: wallpaper (per-monitor), icon
# theme, font via the xsettings channel. No custom GTK theme.
xset() {  # <channel> <property> <value> [type]
    local ch="$1" prop="$2" val="$3" type="${4:-string}"
    apply xfconf-query -c "$ch" -p "$prop" -s "$val" -t "$type" --create || ok=false
}
apply_xfce() {
    echo "desktop=XFCE → applying via xfconf-query"
    command -v xfconf-query >/dev/null 2>&1 || { echo "  xfconf-query missing"; ok=false; return; }

    # Icon theme + font via the xsettings channel.
    xset xsettings /Net/IconThemeName 'PosthogOS'
    if fc-list 2>/dev/null | grep -qi 'inter'; then
        xset xsettings /Gtk/FontName 'Inter 10'
    fi

    # Wallpaper: backdrop image paths are per-monitor/-workspace and named
    # unpredictably (monitor0, monitorVGA-1, …). Set every existing
    # last-image prop; if none exist yet, seed a sane default.
    if [ -f "$wallpaper_light" ]; then
        local props p
        props=$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/last-image$' || true)
        if [ -z "$props" ]; then
            xset xfce4-desktop /backdrop/screen0/monitor0/workspace0/last-image "$wallpaper_light"
        else
            while IFS= read -r p; do
                [ -n "$p" ] && xset xfce4-desktop "$p" "$wallpaper_light"
            done <<<"$props"
        fi
        # image-style 5 = zoomed (best-effort on existing style props).
        while IFS= read -r p; do
            [ -n "$p" ] && apply xfconf-query -c xfce4-desktop -p "$p" -s 5 || true
        done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/image-style$' || true)
    else
        echo "  wallpaper missing: $wallpaper_light"; ok=false
    fi
}

# ───────────────────────── Plasma ────────────────────────────────────────
apply_plasma() {
    echo "desktop=KDE Plasma → applying via plasma-apply-*"
    # Wait for plasmashell on the session DBus; apply commands silently
    # no-op if called before plasmashell subscribes. Short 10s timeout —
    # the rescue service handles the autostart-fires-too-early race at the
    # system level (it polls for kwin and re-invokes us with good env).
    echo "waiting for plasmashell on session DBus..."
    local i ready=0
    for i in $(seq 1 10); do
        if qdbus6 org.kde.plasmashell / >/dev/null 2>&1; then
            echo "  plasmashell ready after ${i}s"; ready=1; break
        fi
        sleep 1
    done
    [ "$ready" = 1 ] || echo "  plasmashell not up in 10s; applying anyway (rescue retries)"

    apply plasma-apply-lookandfeel  -a com.posthog.posthogos || ok=false
    apply plasma-apply-colorscheme  PosthogosLight           || ok=false
    apply plasma-apply-wallpaperimage "$wallpaper"           || ok=false

    # Belt-and-suspenders push via plasmashell's evaluateScript interface.
    # plasma-apply-wallpaperimage returns 0 as long as it could emit the
    # DBus call; if plasmashell wasn't subscribed yet, wallpaper stays default.
    if [ -d "$wallpaper" ] && command -v qdbus6 >/dev/null; then
        local plasma_script
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
    local appletsrc="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
    if [ -f "$appletsrc" ] && ! grep -qF "PosthogosKeyboardGarden" "$appletsrc"; then
        echo "  WARN: wallpaper apply silently no-op'd (path not in $appletsrc)"
        ok=false
    fi

    # ---- Plasma panel customizations ------------------------------------
    # Patch plasma-org.kde.plasma.desktop-appletsrc to:
    #   1. set the Kickoff start-button icon to the PostHog logomark
    #   2. set Kickoff's "Favorites" tab to our preferred app list
    #   3. set the taskbar (icontasks) launchers to our preferred pinned apps
    #
    # We don't replace the whole appletsrc (would fight CachyOS's layout and
    # break on Plasma upgrades). We patch only specific keys on the applets
    # that match known plugin IDs.

    # Taskbar pins, left to right. posthog-code.desktop is conditional (only
    # present if bin/build found an AppImage in PostHog/code's latest release).
    # Plasma renders an unknown .desktop as a "?" placeholder rather than
    # silently dropping it, so we have to filter the list ourselves instead
    # of relying on the launcher to skip missing entries. Calamares isn't
    # pinned: the welcome window's "Install to disk" tile already surfaces it.
    local posthog_code_entry=""
    if [ -f /usr/share/applications/posthog-code.desktop ]; then
        posthog_code_entry="applications:posthog-code.desktop,"
    fi
    local taskbar_launchers="applications:firefox.desktop,applications:com.mitchellh.ghostty.desktop,applications:org.kde.dolphin.desktop,${posthog_code_entry}applications:posthogos-welcome.desktop"
    local kickoff_favorites="applications:firefox.desktop,applications:com.mitchellh.ghostty.desktop,applications:org.kde.dolphin.desktop,${posthog_code_entry}applications:systemsettings.desktop,applications:posthogos-welcome.desktop"

    local appletsrc2="${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"
    echo "+ patching $appletsrc2"
    if [ -f "$appletsrc2" ]; then
        # Read every [Containments][N][Applets][M] section and emit
        # "$cont $applet $plugin" rows so we can dispatch by plugin type.
        local applets
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
        ' "$appletsrc2")

        local patched_kickoff=0 patched_tasks=0 cont applet plugin
        while read -r cont applet plugin; do
            [ -z "$plugin" ] && continue
            case "$plugin" in
                org.kde.plasma.kickoff|org.kde.plasma.kicker|org.kde.plasma.kickerdash|org.kde.plasma.applicationlauncher)
                    kwriteconfig6 --file "$appletsrc2" \
                        --group "Containments" --group "$cont" \
                        --group "Applets" --group "$applet" \
                        --group "Configuration" --group "General" \
                        --key icon posthogos
                    kwriteconfig6 --file "$appletsrc2" \
                        --group "Containments" --group "$cont" \
                        --group "Applets" --group "$applet" \
                        --group "Configuration" --group "General" \
                        --key favorites "$kickoff_favorites"
                    kwriteconfig6 --file "$appletsrc2" \
                        --group "Containments" --group "$cont" \
                        --group "Applets" --group "$applet" \
                        --group "Configuration" --group "General" \
                        --key favoritesPortedToKAstats true
                    patched_kickoff=$((patched_kickoff + 1))
                    echo "  Kickoff[$cont/$applet]: icon + favorites set"
                    ;;
                org.kde.plasma.icontasks|org.kde.plasma.taskmanager|org.kde.plasma.expandingiconspacer)
                    kwriteconfig6 --file "$appletsrc2" \
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
            # DO NOT call refreshCurrentShell or kquitapp+kstart. In Plasma 6
            # refreshCurrentShell tears down and rebuilds the shell, and on
            # QEMU TCG sessions the rebuild fails silently, leaving the user
            # with a black screen. The appletsrc edits we just made apply on
            # the next login, an acceptable trade for not black-screening.
            echo "  appletsrc edits will apply on next login (no live reload)"
        else
            echo "  no kickoff or taskbar applets found (appletsrc layout may differ)"
            ok=false
        fi
    else
        echo "  appletsrc not present yet (plasmashell hasn't written it)"
        ok=false
    fi
}

# ───────────────────────── dispatch ──────────────────────────────────────
de=$(detect_desktop)
echo "detected desktop: $de (XDG_CURRENT_DESKTOP='${XDG_CURRENT_DESKTOP:-}' DESKTOP_SESSION='${DESKTOP_SESSION:-}')"
case "$de" in
    plasma)   apply_plasma ;;
    gnome)    apply_gnome ;;
    cinnamon) apply_cinnamon ;;
    xfce)     apply_xfce ;;
    *)
        echo "unsupported desktop; not applying"
        notify "PosthogOS theme not applied" \
            "PosthogOS branding supports KDE Plasma, GNOME, Cinnamon and XFCE. Your current session ('${XDG_CURRENT_DESKTOP:-unknown}') isn't supported, so nothing was changed."
        # Don't write the marker: if the user switches to a supported desktop
        # later, the next session should apply.
        ok=false
        ;;
esac

if $ok; then
    mkdir -p "$(dirname "$marker")"
    date -Iseconds > "$marker"
    echo "all applied; marker written to $marker"
else
    echo "one or more steps failed (or unsupported desktop); NOT writing marker (will retry next session)"
fi
