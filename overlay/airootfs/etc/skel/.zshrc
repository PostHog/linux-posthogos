# PosthogOS default zshrc.
#
# Every integration is gated on `command -v <tool>` so this file stays
# valid even if a user removes one of the tools post-install. The
# fallback for a missing tool is just "the standard zsh behaviour" for
# that area (no prompt customization, default history, regular cd, etc).
#
# To add personal customization without losing future updates from the OS,
# drop a ~/.zshrc.local; this file sources it at the end if it exists.

# ─── History ──────────────────────────────────────────────────────────────
# Atuin replaces history search but the underlying zsh history file is
# still useful for tab-completion and `!!` patterns, so configure both.
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS

# ─── Completion ───────────────────────────────────────────────────────────
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# ─── Modern tool aliases ──────────────────────────────────────────────────
# Replace classic UNIX tools with their better modern equivalents WHERE
# AVAILABLE. The originals stay reachable via their full path or via
# `command ls` / `\ls` if you need raw POSIX behavior.
if command -v eza >/dev/null; then
    alias ls='eza --group-directories-first'
    alias ll='eza -lhaF --git --group-directories-first --time-style=long-iso'
    alias la='eza -a'
    alias tree='eza --tree --level=3'
fi
if command -v bat >/dev/null; then
    # `cat` stays as POSIX cat by default; bat is for interactive viewing.
    # `view` becomes the "show me this file pretty" shortcut.
    alias view='bat --paging=auto'
    export BAT_THEME="ansi"
fi
command -v fd >/dev/null && alias fd-hidden='fd --hidden --no-ignore'
command -v lazygit >/dev/null && alias lg='lazygit'
command -v lazydocker >/dev/null && alias ld='lazydocker'

# ─── Pure prompt ──────────────────────────────────────────────────────────
# sindresorhus/pure: minimal, async, zsh-only. Shipped pre-baked at
# /usr/share/zsh/pure (customize.sh extracts the upstream tarball there).
# Lightly tinted with PostHog brand colors via prompt symbol / path.
if [[ -d /usr/share/zsh/pure ]]; then
    fpath+=(/usr/share/zsh/pure)
    autoload -U promptinit && promptinit
    # zstyle calls have to come BEFORE `prompt pure` for them to take.
    zstyle :prompt:pure:prompt:success color '#F54E00'   # brand orange on ready
    zstyle :prompt:pure:prompt:error   color '#DC2626'   # brand red on error too
    zstyle :prompt:pure:path           color '#1D4AFF'   # brand blue
    zstyle :prompt:pure:git:branch     color '#EB9D2A'   # brand honey
    zstyle :prompt:pure:git:dirty      color '#F9BD2B'   # brand yellow
    prompt pure 2>/dev/null
fi

# ─── Atuin: history sync + fuzzy search ───────────────────────────────────
# Ctrl-R remapped to atuin's fuzzy search. ↑ key still walks plain
# history (atuin's default --disable-up-arrow is the sane choice).
command -v atuin >/dev/null && eval "$(atuin init zsh --disable-up-arrow)"

# ─── Zoxide: smarter cd ───────────────────────────────────────────────────
# `z foo` jumps to the most-frecency-ranked dir matching "foo".
# `zi` opens an interactive fzf picker over your jump history.
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# ─── FZF keybindings + completions ────────────────────────────────────────
# Ctrl-T  fuzzy-pick files into the current command line
# Alt-C   fuzzy-pick a directory and cd into it
# (Ctrl-R is owned by atuin if installed; falls back to fzf otherwise)
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -r /usr/share/fzf/completion.zsh   ]] && source /usr/share/fzf/completion.zsh

# ─── asdf shims ───────────────────────────────────────────────────────────
# /etc/profile.d/asdf.sh already prepends $ASDF_DATA_DIR/shims to PATH for
# login shells, but interactive non-login shells (terminals opened from a
# running session) need the export here too.
export ASDF_DATA_DIR="${ASDF_DATA_DIR:-$HOME/.asdf}"
[[ ":$PATH:" != *":$ASDF_DATA_DIR/shims:"* ]] && export PATH="$ASDF_DATA_DIR/shims:$PATH"

# ─── User-local overrides ─────────────────────────────────────────────────
# Drop your own aliases / exports / etc. into ~/.zshrc.local and they'll
# be sourced last. This is the place for personal customization without
# touching this file (which gets updated when PosthogOS bumps).
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
