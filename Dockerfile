# Builder image for PosthogOS. Run with --privileged (mkarchiso needs loop
# devices + bind mounts). archlinux is x86_64-only; bin/build handles the
# --platform=linux/amd64 on Apple Silicon (Rosetta-emulated, slow but correct).
#
# Snapshot tag pin (not :latest) for build reproducibility, bump periodically.
FROM archlinux:base-20260510.0.525573

# Pacman 7's alpm seccomp filters fail under Rosetta emulation
# ("seccomp: 22"). Throwaway image, no security impact to disabling.
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
# qt6-base + qt6-declarative: headers for posthogos-welcome's build().
# ~150 MB extra; GH Actions cache absorbs the cost.

# Mark dirs as safe for git. Without this, git's "dubious ownership"
# check fires on Linux bind mounts (host uid != container uid) and
# `git -C upstream archive` aborts. Docker Desktop on macOS papers over
# the uids; Linux runners don't.
RUN git config --system --add safe.directory '*'

# CachyOS repos + keyring. Replicates `cachyos-repo.sh --install` directly
# because the upstream script's `pacman -U` is interactive and hangs in
# non-tty containers.
#
# TODO: bump mirrorlist URLs when upstream releases new versions
#       (cachyos-keyring version is stable across releases).
#
# BUILD_ARCH threads the target arch through the mirror URL.
ARG BUILD_ARCH=x86_64
ARG CACHYOS_MIRROR=https://mirror.cachyos.org/repo/${BUILD_ARCH}/cachyos
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
