# PostHogOS

PostHogOS is a CachyOS-based Arch Linux live ISO with a PostHog-styled KDE desktop, PostHog source code preloaded, and developer tooling baked into the image.

The goal is simple: download the ISO, boot it in a VM or on a machine, and land in a live desktop that already feels like PostHog.

## What is included

- PostHog-styled KDE Plasma desktop theme, wallpaper, panel, launcher, icons, folders, and app surfaces.
- PostHog source checkout under `/opt/posthogos/code/posthog`.
- Developer tools: Docker, Docker Desktop, Cursor, GitHub Desktop, Claude Desktop, Claude Code, Codex CLI, Codex desktop launcher, GitHub CLI, Node.js, pnpm, Bun, Python tooling, Go, Rust, ripgrep, and common build tools.
- Calamares installer entry from the live desktop.

## Download the ISO

Generated ISOs are build artifacts and stay outside Git. The current working ISO is about 4.6 GB.

For a single downloadable ISO, upload it to storage that supports files larger than 4.6 GB and link it from the GitHub Release.

GitHub Release assets currently require each uploaded file to be under 2 GiB, so a GitHub-only release needs split parts:

```bash
split -b 1900m out/desktop/posthogos-desktop-linux-260513.iso \
  out/desktop/posthogos-desktop-linux-260513.iso.part-

sha256sum out/desktop/posthogos-desktop-linux-260513.iso \
  > out/desktop/posthogos-desktop-linux-260513.iso.sha256
```

Download and reassemble split release assets:

```bash
gh release download <release-tag> \
  --repo PostHog/linux-posthogos \
  --pattern '*.iso.part-*' \
  --pattern '*.sha256'

cat posthogos-desktop-linux-260513.iso.part-* \
  > posthogos-desktop-linux-260513.iso

sha256sum -c posthogos-desktop-linux-260513.iso.sha256
```

Boot the ISO in a VM:

```bash
qemu-system-x86_64 \
  -enable-kvm \
  -m 8192 \
  -cpu host \
  -smp 4 \
  -cdrom posthogos-desktop-linux-260513.iso
```

On macOS, drop `-enable-kvm -cpu host`:

```bash
qemu-system-x86_64 \
  -m 8192 \
  -smp 4 \
  -cdrom posthogos-desktop-linux-260513.iso
```

## Pull the source

Clone this branch directly:

```bash
git clone --branch codex/posthogos-bootable-distro \
  https://github.com/PostHog/linux-posthogos.git \
  posthogos-live-iso

cd posthogos-live-iso
```

## Build on macOS

The ISO build itself needs Arch Linux tooling, so macOS builds run inside a privileged Linux container.

Prerequisites:

- Docker Desktop, OrbStack, or Colima with privileged containers enabled.
- At least 30 GB free disk.
- A decent network connection. The first build downloads AUR packages, npm packages, the PostHog repo, and the CachyOS package set.

Build:

```bash
./posthogos/docker-build-iso.sh
```

The ISO lands in:

```bash
out/desktop/
```

To force a rebuild of the local PostHogOS package repo:

```bash
POSTHOGOS_REBUILD_REPO=1 ./posthogos/docker-build-iso.sh
```

## Build on Arch or CachyOS

Install build dependencies:

```bash
sudo pacman -Syu --needed \
  archiso base-devel git git-lfs pacman-contrib squashfs-tools grub \
  nodejs npm pnpm bun cmake go rustup python python-pip python-pipx \
  jq unzip wget curl
```

Build the local package repository first:

```bash
./posthogos/build-local-repo.sh
```

Then build the ISO:

```bash
sudo ./buildiso.sh -p desktop -v -w
```

The ISO lands in:

```bash
out/desktop/
```

## Install from the live desktop

1. Boot the ISO in a VM or on hardware.
2. Choose `Install PostHogOS` from the PostHogOS launcher.
3. Follow the Calamares installer prompts.
4. Reboot into the installed system.

Before publishing a release, verify the ISO boots to the live desktop and completes an install to a virtual disk.

## Release checklist

- Build a fresh ISO from this branch.
- Boot it in a VM.
- Confirm the PostHogOS desktop loads with the PostHog-styled panel, wallpaper, folders, launcher, and app icons.
- Open PostHog code, Cursor, GitHub Desktop, Docker Desktop, Claude Desktop, Claude Code, and Codex CLI/desktop launcher.
- Run a full Calamares install to a qcow2 disk.
- Reboot from that disk.
- Generate a checksum:

```bash
sha256sum out/desktop/*.iso > out/desktop/posthogos.sha256
```

- Upload the `.iso` and `.sha256` files to object storage, or split the ISO and upload the parts plus checksum to a GitHub Release.

## Git hygiene

The source files and package recipes are tracked. Generated build products are intentionally ignored:

- `out/`
- `artifacts/`
- `posthogos/build/`
- `posthogos/repo/`
- package `pkg/`, `src/`, downloaded archives, and built `.pkg.tar.*` files

Keep the ISO as a release asset. Keep the branch as source.
