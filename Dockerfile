# Builder image for PosthogOS. Invoked by bin/build on non-Arch hosts.
# Must run with --privileged: mkarchiso needs loop devices and bind mounts.
#
# archlinux is x86_64-only. On Apple Silicon hosts, build with
# --platform=linux/amd64 (handled by bin/build); OrbStack/Docker Desktop
# emulate via Rosetta. Slow but correct: the final ISO is x86_64 regardless.
#
# Pinned to a specific snapshot tag (not :latest) so builds are reproducible.
# Bump periodically to pick up upstream userspace fixes. The pacman -Syu
# inside this Dockerfile pulls the latest package versions on top regardless,
# so the pin mainly controls the starting glibc/coreutils/etc snapshot.
FROM archlinux:base-20260510.0.525573

# Pacman 7's alpm sandbox uses seccomp filters that fail under Rosetta
# emulation ("error restricting syscalls via seccomp: 22"). Disable it.
# This image is throwaway, no security impact.
RUN echo 'DisableSandbox' >> /etc/pacman.conf

RUN pacman -Syu --noconfirm --needed \
    archiso \
    mkinitcpio-archiso \
    git \
    squashfs-tools \
    grub \
    rsync \
    sudo \
    base-devel \
    imagemagick \
    librsvg \
    qt6-base \
    qt6-declarative \
 && pacman -Scc --noconfirm
# qt6-base + qt6-declarative are needed by posthogos-welcome's PKGBUILD
# build(), which compiles a small C++ launcher (~30 lines) against Qt6
# Core/Gui/Qml. Adds ~150 MB to the image but the GH Actions pacman
# cache absorbs the download cost on subsequent builds.

# Mark all dirs as safe for git. Without this, git refuses to operate on
# bind-mounted workspaces when the host file owner uid (e.g. 1001 on GitHub
# Actions runners) doesn't match the container's runtime uid (0/root). The
# Docker-Desktop case works by accident because OSXFS papers over the uids;
# Linux bind mounts don't, so git's "dubious ownership" check fires and
# `git -C upstream archive` in scripts/in-container-build.sh aborts.
RUN git config --system --add safe.directory '*'

# CachyOS-specific repos and keyring. mkarchiso runs pacstrap inside the
# container; without these, cachyos-* packages from upstream/archiso/
# packages_desktop.x86_64 won't resolve.
#
# We replicate CachyOS's `cachyos-repo.sh --install` directly because the
# upstream script's `pacman -U` call is interactive (no --noconfirm) and
# hangs on `Y/n` in non-tty containers.
#
# TODO: Mirrorlist package versions are pinned. When upstream releases new
#       versions, bump the URLs below. The cachyos-keyring version is
#       stable across releases.
ARG CACHYOS_MIRROR=https://mirror.cachyos.org/repo/x86_64/cachyos
RUN pacman-key --init \
 && pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com \
 && pacman-key --lsign-key F3B607488DB35A47 \
 && pacman -U --noconfirm \
      "${CACHYOS_MIRROR}/cachyos-keyring-20240331-1-any.pkg.tar.zst" \
      "${CACHYOS_MIRROR}/cachyos-mirrorlist-27-1-any.pkg.tar.zst" \
      "${CACHYOS_MIRROR}/cachyos-v3-mirrorlist-27-1-any.pkg.tar.zst" \
      "${CACHYOS_MIRROR}/cachyos-v4-mirrorlist-27-1-any.pkg.tar.zst" \
 && printf '\n[cachyos-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist\n\n[cachyos-core-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist\n\n[cachyos-extra-v3]\nInclude = /etc/pacman.d/cachyos-v3-mirrorlist\n\n[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n' >> /etc/pacman.conf \
 && pacman -Sy --noconfirm \
 && pacman -Scc --noconfirm

WORKDIR /work
