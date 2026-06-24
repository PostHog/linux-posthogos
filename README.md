# PosthogOS

## Getting PosthogOS

### Downloading a release ISO

A custom-styled CachyOS KDE spin that Forks [CachyOS/CachyOS-Live-ISO](https://github.com/CachyOS/CachyOS-Live-ISO) and rebrands the boot splash, login screen, desktop, and installer.

Each release on the [releases page](https://github.com/PostHog/linux-posthogos/releases) ships the ISO and the signed `posthogos-*` pacman packages. Download all `.partNN` files for the release and reassemble:

```bash
cat posthogos-desktop-linux-vX.Y.Z.iso.part?? > posthogos-desktop-linux-vX.Y.Z.iso
```

Verify the result:

```bash
file posthogos-desktop-linux-vX.Y.Z.iso
#   posthogos-...iso: DOS/MBR boot sector; partition 1 ...
```

Then flash to a USB stick (`dd`, balenaEtcher, Rufus, etc.) and boot.

### Applying to an existing install

PosthogOS publishes its branding (icons, wallpapers, look-and-feel) as signed repos for both package managers, so an existing KDE Plasma install can pull it without reinstalling. The activation is the same either way: a firstrun autostart entry applies the look-and-feel on your next login.

#### Arch / CachyOS (pacman)

The Arch repo (`https://posthog.github.io/linux-posthogos/$arch`) carries the full `posthogos-*` stack.

1. Register the `[posthogos]` repo by appending to `/etc/pacman.conf`:

   ```bash
   sudo tee -a /etc/pacman.conf >/dev/null <<'EOF'

   [posthogos]
   SigLevel = Required
   Server = https://posthog.github.io/linux-posthogos/$arch
   EOF
   ```

2. Temporarily relax signature checking to bootstrap trust:

   ```bash
   sudo pacman -Sy --noconfirm --overwrite='*' \
     --config <(sed 's/SigLevel = Required/SigLevel = Optional TrustAll/' /etc/pacman.conf) \
     posthogos-keyring
   ```

   The keyring's install hook locally signs the packager key into `/etc/pacman.d/gnupg/`, so every `posthogos-*` signature is trusted from here on.

3. Install the branding and refresh:

   ```bash
   sudo pacman -Syu posthogos-branding posthogos-scripts
   ```

4. Log out and back in. An autostart entry applies the look-and-feel, color scheme, and wallpaper to your account on next login.

After this, plain `sudo pacman -Syu` picks up new branding versions whenever a release is published.

#### Debian / Ubuntu (apt)

The apt repo (`https://posthog.github.io/linux-posthogos/deb`) ships `posthogos-branding` and `posthogos-scripts` as `.deb`s (the rest of the stack is Arch-specific). Requires a KDE Plasma desktop.

1. Trust the packager key and register the repo:

   ```bash
   sudo install -d /etc/apt/keyrings
   sudo curl -fsSL https://posthog.github.io/linux-posthogos/deb/posthogos.gpg \
     -o /etc/apt/keyrings/posthogos.gpg
   echo 'deb [signed-by=/etc/apt/keyrings/posthogos.gpg] https://posthog.github.io/linux-posthogos/deb stable main' \
     | sudo tee /etc/apt/sources.list.d/posthogos.list >/dev/null
   ```

2. Install the branding:

   ```bash
   sudo apt update
   sudo apt install posthogos-branding posthogos-scripts
   ```

3. Log out and back in — same firstrun activation as above.

After this, `sudo apt update && sudo apt upgrade` picks up new branding versions. (Standalone `.deb`s are also attached to each release for offline `apt install ./posthogos-*.deb`.)

## Building & architecture

### Repo layout

```
.
├── bin/                  # host scripts (build, test, setup, clean)
├── scripts/              # scripts that run inside the build container
├── Dockerfile            # Arch + archiso build image (for macOS hosts)
├── upstream/             # git submodule → CachyOS/CachyOS-Live-ISO (do not edit)
├── overlay/              # files merged into upstream/archiso/airootfs/ at build time
│                         #   mirrors the airootfs/ layout exactly
├── packages/             # PosthogOS pacman repo (one PKGBUILD per package)
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

### Cloning

This repo uses a submodule for upstream. Clone with:

```bash
git clone --recurse-submodules <repo-url>
# or, if already cloned:
git submodule update --init
```

`bin/setup` and `bin/build` will auto-init the submodule if missing.

### Prerequisites

#### macOS host (local iteration)

- Docker Desktop (or OrbStack / Colima with `--privileged` support)
- QEMU for booting the output ISO: `brew install qemu`
- ~20 GB free disk for the build tree + ISO output

`mkarchiso` does not run on macOS directly. `bin/build` invokes it inside a privileged Arch container.

#### Arch / CachyOS host (production builds)

- `archiso`, `mkinitcpio-archiso`, `git`, `squashfs-tools`, `grub` installed
- `qemu-desktop`, `edk2-ovmf` for testing

On a real Arch host you can skip Docker. `bin/build --native` runs `buildiso.sh` directly.

### Usage

```bash
bin/setup     # verify host has docker + qemu
bin/build     # produce out/<iso_name>-<date>-x86_64.iso
bin/build-deb # build .deb packages + apt repo from out/pkgs (after bin/build)
bin/test      # boot the latest ISO in QEMU
bin/clean     # rm -rf build/ out/
```

### How the build works

1. `bin/build` builds the `posthogos-builder` Docker image (`Dockerfile`).
2. It runs the image with `--privileged` and the repo bind-mounted at `/work`.
3. Inside the container, [scripts/in-container-build.sh](scripts/in-container-build.sh):
   - Copies `upstream/` to a writable build directory.
   - Rsyncs `overlay/` onto `archiso/airootfs/` (overlay wins).
   - Drops `scripts/posthogos-customize.sh` into the airootfs so it runs at chroot time.
   - Invokes `./buildiso.sh -p desktop -v -w` (upstream's wrapper around `mkarchiso`).
4. The resulting `.iso` is copied back to `./out/`.

The chroot hook ([scripts/posthogos-customize.sh](scripts/posthogos-customize.sh)) handles things the overlay can't express as static files: regenerating the initramfs with the Plymouth theme baked in, patching `/etc/calamares/settings.conf` to point at our branding, refreshing icon/gtk caches, enabling SDDM.

The branding also ships as pacman packages built from `packages/`. The release workflow signs them, pushes the repo to `gh-pages`, and pacstraps `posthogos-keyring` + `posthogos-branding` into the ISO so installed systems start with pacman-owned, signed files. See [packages/README.md](packages/README.md).

For Debian/Ubuntu, [scripts/build-deb-packages.sh](scripts/build-deb-packages.sh) repackages the portable `posthogos-branding` + `posthogos-scripts` pacman packages into `.deb`s (relocating `/usr/local/bin` → `/usr/bin` per Debian policy) and assembles a signed apt repo, published to `gh-pages` under `deb/`. Run it locally with `bin/build-deb` (after `bin/build`).

### Branding scope

- Boot splash: Plymouth theme `posthogos` (`/usr/share/plymouth/themes/posthogos/`)
- Login screen: SDDM theme `posthogos` (`/usr/share/sddm/themes/posthogos/`)
- Desktop: Plasma look-and-feel `posthogos`, matching color scheme, GTK theme, wallpaper
- Installer: Calamares branding `posthogos` (logo, slideshow, support URLs)
- ISO identity: rebranded `os-release`, `lsb-release`, boot menu titles, ISO label `POSTHOGOS_YYYYMM`

CachyOS's own branding packages (`cachyos-kde-settings`, `cachyos-themes-sddm`, `cachyos-calamares-next`, `cachyos-hello`) stay installed; their files are shadowed by `overlay/` or patched by the chroot hook. This avoids forking those packages.
