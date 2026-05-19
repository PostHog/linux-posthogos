# PosthogOS

A custom-styled CachyOS KDE spin. Forks [CachyOS/CachyOS-Live-ISO](https://github.com/CachyOS/CachyOS-Live-ISO) and rebrands the boot splash, login screen, desktop, and installer.

The output is a bootable `.iso` that runs as a live environment and installs to disk via a re-branded Calamares.

## Repo layout

```
.
├── bin/                  # host scripts (build, test, setup, clean)
├── scripts/              # scripts that run inside the build container
├── Dockerfile            # Arch + archiso build image (for macOS hosts)
├── upstream/             # git submodule → CachyOS/CachyOS-Live-ISO (do not edit)
├── overlay/              # files merged into upstream/archiso/airootfs/ at build time
│                         #   mirrors the airootfs/ layout exactly
└── branding/posthogos/   # source artwork (logo SVG, wallpaper, slideshow PNGs)
```

`upstream/` is a git submodule pinned to a specific CachyOS-Live-ISO commit. The pin lives in this repo's index (see `git submodule status`). Never edit `upstream/` in place. All customisations live in `overlay/` or `scripts/posthogos-customize.sh`, applied on top at build time. This keeps upstream bumps tractable.

### Bumping upstream

```bash
cd upstream && git fetch && git checkout <new-sha> && cd ..
git add upstream
git commit -m "upstream: bump to <new-sha>"
```

Or `git submodule update --remote upstream` to track upstream `master` directly (less controlled; prefer pinning explicit SHAs).

## Cloning

This repo uses a submodule for upstream. Clone with:

```bash
git clone --recurse-submodules <repo-url>
# or, if already cloned:
git submodule update --init
```

`bin/setup` and `bin/build` will auto-init the submodule if missing.

## Prerequisites

### macOS host (local iteration)

- Docker Desktop (or OrbStack / Colima with `--privileged` support)
- QEMU for booting the output ISO: `brew install qemu`
- ~20 GB free disk for the build tree + ISO output

`mkarchiso` does not run on macOS directly. `bin/build` invokes it inside a privileged Arch container.

### Arch / CachyOS host (production builds)

- `archiso`, `mkinitcpio-archiso`, `git`, `squashfs-tools`, `grub` installed
- `qemu-desktop`, `edk2-ovmf` for testing

On a real Arch host you can skip Docker. `bin/build --native` runs `buildiso.sh` directly.

## Usage

```bash
bin/setup     # verify host has docker + qemu
bin/build     # produce out/<iso_name>-<date>-x86_64.iso
bin/test      # boot the latest ISO in QEMU
bin/clean     # rm -rf build/ out/
```

## Downloading a release ISO

Each release on the [releases page](https://github.com/PostHog/linux-posthogos/releases) ships the ISO and the signed `posthogos-*` pacman packages.

The ISO is ~3 GB, which exceeds GitHub's 2 GiB per-asset cap on release downloads, so it's split into ~1.9 GiB chunks (`posthogos-desktop-linux-vX.Y.Z.iso.part00`, `.part01`, …). Download all `.partNN` files for the release and reassemble:

```bash
cat posthogos-desktop-linux-vX.Y.Z.iso.part?? > posthogos-desktop-linux-vX.Y.Z.iso
```

Order matters but `cat` with the `??` glob handles it (chunks are zero-padded and sort lexicographically). Verify the result:

```bash
file posthogos-desktop-linux-vX.Y.Z.iso
#   posthogos-...iso: DOS/MBR boot sector; partition 1 ...
```

Then flash to a USB stick (`dd`, balenaEtcher, Rufus, etc.) and boot. PosthogOS team members can also pull the unsplit ISO from the workflow run's "posthogos-vX.Y.Z" artifact (requires GitHub login, 90-day retention).

## How the build works

1. `bin/build` builds the `posthogos-builder` Docker image (`Dockerfile`).
2. It runs the image with `--privileged` and the repo bind-mounted at `/work`.
3. Inside the container, [scripts/in-container-build.sh](scripts/in-container-build.sh):
   - Copies `upstream/` to a writable build directory.
   - Rsyncs `overlay/` onto `archiso/airootfs/` (overlay wins).
   - Drops `scripts/posthogos-customize.sh` into the airootfs so it runs at chroot time.
   - Invokes `./buildiso.sh -p desktop -v -w` (upstream's wrapper around `mkarchiso`).
4. The resulting `.iso` is copied back to `./out/`.

The chroot hook ([scripts/posthogos-customize.sh](scripts/posthogos-customize.sh)) handles things the overlay can't express as static files: regenerating the initramfs with the Plymouth theme baked in, patching `/etc/calamares/settings.conf` to point at our branding, refreshing icon/gtk caches, enabling SDDM.

## Branding scope

- Boot splash: Plymouth theme `posthogos` (`/usr/share/plymouth/themes/posthogos/`)
- Login screen: SDDM theme `posthogos` (`/usr/share/sddm/themes/posthogos/`)
- Desktop: Plasma look-and-feel `posthogos`, matching color scheme, GTK theme, wallpaper
- Installer: Calamares branding `posthogos` (logo, slideshow, support URLs)
- ISO identity: rebranded `os-release`, `lsb-release`, boot menu titles, ISO label `POSTHOGOS_YYYYMM`

CachyOS's own branding packages (`cachyos-kde-settings`, `cachyos-themes-sddm`, `cachyos-calamares-next`, `cachyos-hello`) stay installed; their files are shadowed by `overlay/` or patched by the chroot hook. This avoids forking those packages.

## Remote access

The Plasma 6 built-in RDP server (`krdp` package) is pre-installed. It's off by default; enable it via System Settings → Remote Desktop (set a password, toggle on). RDP listens on TCP 3389; connect with any RDP client (`xfreerdp`, mstsc, Microsoft Remote Desktop).

### Enabling on a headless session

```bash
sudo loginctl enable-linger "$USER"                  # keep the user manager alive after logout
krdpservercli add-user "$USER"                       # interactive password prompt
systemctl --user enable --now plasma-krdp_server.service
```

Then connect with any RDP client:

```bash
# Linux
xfreerdp /v:<vps-ip> /u:<user> /cert:ignore
# macOS: Microsoft Remote Desktop → Add PC → <vps-ip>:3389
# Windows: mstsc.exe /v:<vps-ip>:3389
```

First connection warns about a self-signed TLS cert, which is expected; krdp regenerates it on first start. To tear down: `systemctl --user disable --now plasma-krdp_server.service`.

## Verification checklist

Run end-to-end before declaring a build done:

- [ ] ISO boots in UEFI mode in QEMU
- [ ] Boot menu shows PosthogOS titles, not CachyOS
- [ ] Plymouth splash shows the PosthogOS logo
- [ ] SDDM greeter uses the PosthogOS theme
- [ ] Desktop session loads with PosthogOS wallpaper + colour scheme
- [ ] `cat /etc/os-release` in the live env shows `PRETTY_NAME="PosthogOS"`
- [ ] Calamares opens with PosthogOS branding + slideshow
- [ ] Full install to a qcow2 disk completes; installed system boots with branding intact
- [ ] System Settings → Remote Desktop is present; toggling it on lets an `xfreerdp` connection from the host land in Plasma

## Out of scope

- ISO signing / Secure Boot
- ISO hosting / distribution
- Custom pacman repo for shipping packaged themes
- CI (build on push); iterate locally first
