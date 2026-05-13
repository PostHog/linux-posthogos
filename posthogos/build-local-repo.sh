#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_root="$root/posthogos/repo"
repo_dir="$repo_root/x86_64"
aur_dir="$root/posthogos/build/aur"
codex_desktop_dir="$root/posthogos/build/codex-desktop-linux"

aur_packages=(
  cursor-bin
  docker-desktop
  github-desktop-bin
  claude-desktop-bin
)

local_package_dirs=(
  "$root/posthogos/packages/posthogos-ai-clis"
  "$root/posthogos/packages/posthogos-branding"
  "$root/posthogos/packages/posthogos-posthog-code"
)

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

require_arch_build_host() {
  if ! command -v pacman >/dev/null 2>&1 || ! command -v makepkg >/dev/null 2>&1; then
    cat >&2 <<'EOF'
This must run on an Arch or CachyOS build host.

It builds pacman packages and an archiso local repository. On macOS, use a
CachyOS/Arch VM or Linux builder, then run buildiso.sh from this checkout.
EOF
    exit 1
  fi
}

configure_pacman_repo() {
  local conf="$root/archiso/pacman.conf"
  local tmp block
  tmp="$(mktemp)"
  block="$(cat <<EOF
# BEGIN PostHogOS local repo
[posthogos-local]
SigLevel = Optional TrustAll
Server = file://${repo_root}/\$arch
# END PostHogOS local repo

EOF
)"

  awk -v block="$block" '
    $0 == "# BEGIN PostHogOS local repo" { skip = 1; next }
    $0 == "# END PostHogOS local repo" { skip = 0; next }
    skip { next }
    !inserted && $0 == "[cachyos]" { print block; inserted = 1 }
    { print }
    END { if (!inserted) print block }
  ' "$conf" > "$tmp"

  mv "$tmp" "$conf"
}

build_pkg_dir() {
  local pkg_dir="$1"
  printf '\n==> Building %s\n' "$(basename "$pkg_dir")"
  (
    cd "$pkg_dir"
    rm -f ./*.pkg.tar.*
    makepkg -sf --noconfirm --needed --cleanbuild
  )
  cp "$pkg_dir"/*.pkg.tar.* "$repo_dir/"
}

build_aur_pkg() {
  local pkg="$1"
  local checkout="$aur_dir/$pkg"

  printf '\n==> Building AUR package %s\n' "$pkg"
  if [ -d "$checkout/.git" ]; then
    git -C "$checkout" pull --ff-only
  else
    git clone "https://aur.archlinux.org/${pkg}.git" "$checkout"
  fi

  (
    cd "$checkout"
    rm -f ./*.pkg.tar.*
    makepkg -sf --noconfirm --needed --cleanbuild
  )
  cp "$checkout"/*.pkg.tar.* "$repo_dir/"
}

build_codex_desktop() {
  printf '\n==> Building Codex Desktop Linux package\n'

  if [ -d "$codex_desktop_dir/.git" ]; then
    git -C "$codex_desktop_dir" pull --ff-only
  else
    git clone https://github.com/ilysenko/codex-desktop-linux.git "$codex_desktop_dir"
  fi

  (
    cd "$codex_desktop_dir"
    if [ -x scripts/install-deps.sh ]; then
      ./scripts/install-deps.sh
    fi
    if [ -f "$HOME/.cargo/env" ]; then
      # The Codex Linux installer bootstraps Rust through rustup.
      # make pacman needs cargo on PATH immediately after that bootstrap.
      # shellcheck disable=SC1091
      . "$HOME/.cargo/env"
    fi
    make build-app
    make pacman
  )

  cp "$codex_desktop_dir"/dist/codex-desktop-*.pkg.tar.* "$repo_dir/"
}

main() {
  require_arch_build_host
  need_cmd git
  need_cmd repo-add

  mkdir -p "$repo_dir" "$aur_dir"
  rm -f "$repo_dir"/*.pkg.tar.* "$repo_dir"/posthogos-local.db*

  for pkg in "${aur_packages[@]}"; do
    build_aur_pkg "$pkg"
  done

  build_codex_desktop

  for pkg_dir in "${local_package_dirs[@]}"; do
    build_pkg_dir "$pkg_dir"
  done

  repo-add "$repo_dir/posthogos-local.db.tar.gz" "$repo_dir"/*.pkg.tar.*
  configure_pacman_repo

  cat <<EOF

PostHogOS local repo is ready:
  $repo_dir

Next:
  sudo ./buildiso.sh -p desktop -v -w

EOF
}

main "$@"
