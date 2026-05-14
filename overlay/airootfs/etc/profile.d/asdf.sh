# asdf-vm shell integration for all users.
#
# asdf (the runtime version manager — handles Node/Python/Rust/Go/etc per
# project via .tool-versions files) needs its `shims` directory on PATH for
# its installed runtimes to be invocable. Modern asdf (v0.16+, the Go
# rewrite shipped by Arch's `asdf-vm` package) doesn't require sourcing a
# big shell script anymore — just two env vars do the work.
#
# ASDF_DATA_DIR  per-user state location. Defaults to ~/.asdf; setting it
#                explicitly here makes the path unambiguous even when $HOME
#                is unusual (e.g., during system services that inherit env
#                from somewhere odd).
# PATH            prepend $ASDF_DATA_DIR/shims so the version-managed
#                binaries (`node`, `python`, `cargo`, etc.) win over the
#                pacman-installed system versions in /usr/bin when a user
#                has asdf-installed versions for those runtimes. Without
#                asdf installs, the shims dir doesn't exist and PATH just
#                contains a non-existent entry (harmless).
#
# Note for system tasks (AI CLI installs, system scripts that need a
# guaranteed node): use /usr/bin/node explicitly. The asdf shim layer
# would resolve to a per-user runtime that doesn't exist in system context.
# This is by design — asdf is a per-user / per-project layer, pacman owns
# the system-wide layer underneath.

export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"
export PATH="$ASDF_DATA_DIR/shims:$PATH"
