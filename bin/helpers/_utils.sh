#!/usr/bin/env bash

# Common utility functions for bin/ scripts.

print_color() {
    case $1 in
        red)    echo -e "\033[31m$2\033[0m";;
        green)  echo -e "\033[32m$2\033[0m";;
        yellow) echo -e "\033[33m$2\033[0m";;
        blue)   echo -e "\033[34m$2\033[0m";;
        *)      echo "$2";;
    esac
}

error()   { print_color red    "Error: $*" >&2; }
warning() { print_color yellow "Warning: $*" >&2; }
success() { print_color green  "✓ $*"; }
fatal()   { error "$*"; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

require_commands() {
    local missing=()
    for cmd in "$@"; do
        command_exists "$cmd" || missing+=("$cmd")
    done
    [ ${#missing[@]} -eq 0 ] || fatal "Missing commands: ${missing[*]}"
}

# cd to the repo root (parent of bin/)
set_source_and_root_dir() {
    { set +x; } 2>/dev/null
    source_dir="$( cd -P "$( dirname "$0" )" >/dev/null 2>&1 && pwd )"
    root_dir=$(cd "$source_dir" && cd ../ && pwd)
    cd "$root_dir"
}

# Print the script header (lines starting with #/) as help text.
# -E for extended regex: BSD sed (macOS) doesn't honor \? in basic regex.
show_help() {
    sed -nE 's|^#/ ?||p' "$0"
}
