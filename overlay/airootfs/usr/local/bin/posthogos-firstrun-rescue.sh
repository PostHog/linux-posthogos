#!/usr/bin/env bash
# Rescue path for posthogos-firstrun.sh.
#
# The autostart entry at /etc/xdg/autostart/posthogos-firstrun.desktop fires
# at user-session start. On a live ISO that autologins straight into Plasma,
# the autostart can fire BEFORE plasmashell has subscribed to the session
# DBus, and plasma-apply-* commands silently no-op when that happens
# (returning success but doing nothing). Our firstrun.sh waits 10s and
# verifies the wallpaper landed, but if the verify fails it leaves the
# marker unwritten.
#
# This service runs as root after display-manager.service, polls for
# kwin_wayland / kwin_x11 to appear under a Plasma session uid (≥ 1000),
# snoops /proc/$pid/environ to harvest the real session env (DBus address,
# XDG_RUNTIME_DIR, wayland/X display, etc.), then re-invokes firstrun.sh
# inside that user's session via `runuser`. Belt and suspenders.
#
# Idempotent through firstrun.sh's marker file. If autostart won the race
# and wrote the marker, this is a fast no-op.
#
# Lifted from CachyOS contributor Will's posthogos-live-session-rescue
# (origin/codex/posthogos-bootable-distro), trimmed for Wayland-only +
# our marker pattern.

set -euo pipefail

log=/tmp/posthogos-firstrun-rescue.log
exec >>"$log" 2>&1
echo "===== $(date -Iseconds) posthogos-firstrun-rescue starting (uid=$(id -u)) ====="

# --- Find the Plasma session user ----------------------------------------
# Any kwin process owned by a uid ≥ 1000 (excludes systemd-coredump, etc.).
# Returns the username on stdout; rc 1 if none found.
find_session_user() {
    local pid uid
    for pid in $(pgrep -x kwin_wayland 2>/dev/null) $(pgrep -x kwin_x11 2>/dev/null); do
        uid=$(awk '/^Uid:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null || true)
        [ -n "$uid" ] && [ "$uid" -ge 1000 ] || continue
        getent passwd "$uid" | awk -F: '{print $1; exit}'
        return 0
    done
    return 1
}

# --- Harvest session env from kwin / plasmashell -------------------------
# We probe each candidate process owned by $user until we find one whose
# /proc/<pid>/environ contains both DBUS_SESSION_BUS_ADDRESS and
# XDG_RUNTIME_DIR. Those are the bare minimum to talk to plasmashell.
capture_env() {
    local user="$1" out="$2" pid uid
    uid=$(id -u "$user" 2>/dev/null) || return 1
    for pid in $(pgrep -u "$uid" -x kwin_wayland 2>/dev/null) \
               $(pgrep -u "$uid" -x kwin_x11 2>/dev/null) \
               $(pgrep -u "$uid" -x plasmashell 2>/dev/null); do
        [ -r "/proc/$pid/environ" ] || continue
        tr '\0' '\n' < "/proc/$pid/environ" > "$out.tmp" 2>/dev/null || continue
        if grep -q '^DBUS_SESSION_BUS_ADDRESS=' "$out.tmp" \
            && grep -q '^XDG_RUNTIME_DIR=' "$out.tmp"; then
            mv "$out.tmp" "$out"
            return 0
        fi
    done
    rm -f "$out.tmp"
    return 1
}

# --- Wait for a Plasma session to appear (up to 90s) ---------------------
# 90s is generous: autologin → DM → kwin typically lands in 10-15s, but a
# slow VM (Apple Silicon TCG, especially) can take 60s+.
echo "waiting for kwin..."
user=""
elapsed=0
for elapsed in $(seq 1 90); do
    user=$(find_session_user) && break || true
    sleep 1
done

if [ -z "$user" ]; then
    echo "no kwin process found after 90s; giving up (no live Plasma session?)"
    exit 0
fi
echo "  found session user: $user (after ${elapsed}s)"

# --- Marker short-circuit ------------------------------------------------
# If autostart already ran firstrun.sh to completion (marker written),
# there's nothing to do. The autostart's marker write is gated on a verify
# step, so a present marker means apply DID land.
home=$(getent passwd "$user" | awk -F: '{print $6}')
marker="$home/.config/posthogos-firstrun-applied"
if [ -f "$marker" ]; then
    echo "marker present at $marker, autostart won the race; nothing to do"
    exit 0
fi
echo "marker absent, autostart hasn't completed; will run firstrun"

# --- Harvest env (up to 30s) ---------------------------------------------
env_file=$(mktemp /tmp/posthogos-firstrun-rescue-env.XXXXXX)
trap 'rm -f "$env_file" "$env_file.tmp"' EXIT

echo "harvesting session env from kwin/plasmashell..."
for elapsed in $(seq 1 30); do
    capture_env "$user" "$env_file" && break || true
    sleep 1
done

if [ ! -s "$env_file" ]; then
    echo "  couldn't capture DBUS_SESSION_BUS_ADDRESS from kwin's env in 30s; bailing"
    exit 0
fi
echo "  captured env (${elapsed}s elapsed)"

# --- Build env passthrough + invoke firstrun.sh --------------------------
# These are the env vars firstrun.sh needs to drive Plasma. HOME so $HOME
# resolves correctly post-runuser; XDG_CONFIG_HOME isn't always set, and
# kwriteconfig6 expects $HOME/.config when it's missing.
env_args=()
for key in DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR \
           WAYLAND_DISPLAY DISPLAY XAUTHORITY \
           XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP XDG_SESSION_TYPE \
           KDE_SESSION_VERSION KDE_FULL_SESSION \
           LANG LC_ALL; do
    val=$(grep -m1 "^${key}=" "$env_file" | cut -d= -f2- || true)
    [ -n "${val:-}" ] && env_args+=("$key=$val")
done
# Always set HOME explicitly. runuser doesn't always re-resolve it.
env_args+=("HOME=$home")

echo "invoking /usr/local/bin/posthogos-firstrun.sh as $user (${#env_args[@]} env vars)"
runuser -u "$user" -- env -i "${env_args[@]}" PATH=/usr/local/bin:/usr/bin:/bin \
    /usr/local/bin/posthogos-firstrun.sh || echo "  firstrun.sh exited non-zero (already logged to its own log)"

if [ -f "$marker" ]; then
    echo "done; marker written"
else
    echo "done; marker STILL MISSING (firstrun reported failure)"
fi
