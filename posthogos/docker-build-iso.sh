#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${POSTHOGOS_BUILDER_IMAGE:-cachyos/cachyos:latest}"
platform="${POSTHOGOS_BUILDER_PLATFORM:-linux/amd64}"
uid="$(id -u)"
gid="$(id -g)"
user_name="posthogos"
work_volume="${POSTHOGOS_WORK_VOLUME:-posthogos-iso-work}"

docker run --rm \
  --platform "$platform" \
  --privileged \
  --name posthogos-iso-builder \
  -e POSTHOGOS_HOST_UID="$uid" \
  -e POSTHOGOS_HOST_GID="$gid" \
  -e POSTHOGOS_USER="$user_name" \
  -e POSTHOGOS_REBUILD_REPO="${POSTHOGOS_REBUILD_REPO:-0}" \
  -e POSTHOGOS_WORK_DIR="/posthogos-work/build" \
  -e POSTHOGOS_OUT_DIR="/work/out" \
  -v "$root:/work" \
  -v "$work_volume:/posthogos-work" \
  -w /work \
  "$image" \
  bash -lc '
set -euo pipefail

uid="${POSTHOGOS_HOST_UID}"
gid="${POSTHOGOS_HOST_GID}"
user_name="${POSTHOGOS_USER}"
work_dir="${POSTHOGOS_WORK_DIR}"
out_dir="${POSTHOGOS_OUT_DIR}"

pacman -Syu --noconfirm
pacman -S --needed --noconfirm \
  archiso \
  base-devel \
  bun \
  ca-certificates \
  cmake \
  curl \
  fakeroot \
  git \
  git-lfs \
  go \
  grub \
  jq \
  make \
  ninja \
  nodejs \
  npm \
  pacman-contrib \
  pnpm \
  protobuf \
  python \
  python-pip \
  python-pipx \
  sudo \
  unzip \
  uv \
  wget

if ! getent group "$gid" >/dev/null 2>&1; then
  groupadd -g "$gid" "$user_name"
fi

if ! id -u "$user_name" >/dev/null 2>&1; then
  useradd -m -u "$uid" -g "$gid" -s /bin/bash "$user_name"
fi

printf "%s ALL=(ALL) NOPASSWD: ALL\n" "$user_name" > /etc/sudoers.d/posthogos
chmod 0440 /etc/sudoers.d/posthogos
mkdir -p "$(dirname "$work_dir")" "$out_dir"
chown -R "$uid:$gid" "$(dirname "$work_dir")" "$out_dir"

sudo -u "$user_name" git config --global --add safe.directory /work
if [ "${POSTHOGOS_REBUILD_REPO:-0}" = "1" ] || [ ! -f /work/posthogos/repo/x86_64/posthogos-local.db.tar.gz ]; then
  sudo -u "$user_name" bash -lc "cd /work && ./posthogos/build-local-repo.sh"
else
  printf "\n==> Reusing existing PostHogOS local repo\n"
fi
sudo -u "$user_name" env POSTHOGOS_WORK_DIR="$work_dir" POSTHOGOS_OUT_DIR="$out_dir" bash -lc "cd /work && ./buildiso.sh -p desktop -v -w"
'
