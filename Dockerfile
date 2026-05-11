# Builder image for PosthogOS. Invoked by bin/build on non-Arch hosts.
# Must run with --privileged: mkarchiso needs loop devices and bind mounts.
FROM archlinux:latest

RUN pacman -Syu --noconfirm --needed \
    archiso \
    mkinitcpio-archiso \
    git \
    squashfs-tools \
    grub \
    rsync \
    sudo \
    base-devel \
 && pacman -Scc --noconfirm

# CachyOS-specific repos and keyring. mkarchiso runs pacstrap inside the
# container; without these, cachyos-* packages from upstream/archiso/
# packages_desktop.x86_64 won't resolve.
#
# TODO: The keyring/mirrorlist package URLs below need to be current. Check
#       https://mirror.cachyos.org/repo/x86_64/cachyos/ and update versions
#       on first build. Pin to specific versions once it works.
RUN pacman-key --init \
 && curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz | tar -xJ -C /tmp \
 && cd /tmp/cachyos-repo && ./cachyos-repo.sh --install || \
    echo "WARN: cachyos-repo bootstrap failed; verify Dockerfile keyring step"

WORKDIR /work
