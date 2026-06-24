# packages/

PosthogOS as a pacman repository.

## What and why

Everything PosthogOS adds on top of CachyOS (icons, wallpapers, Plasma
look-and-feel, fonts, scripts, the welcome window) needs an update
path. Without one, brand iteration is frozen at whatever ISO each user
installed from.

The pacman repo hosted at `https://posthog.github.io/linux-posthogos/$arch`
(GitHub Pages from this repo's `gh-pages` branch) closes that gap. Each
`packages/<pkgname>/PKGBUILD` produces a `.pkg.tar.zst` that an installed
PosthogOS can `pacman -Syu` to receive.

## Currently shipping

- **posthogos-keyring**: the PostHog packager GPG public key. Installs the
  pubring at `/usr/share/pacman/keyrings/posthogos.gpg` and locally signs
  it into `/etc/pacman.d/gnupg/` via a pacman hook, so the system trusts
  every `posthogos-*` signature from first boot. Required for the
  end-user `[posthogos]` repo's `SigLevel = Required`.
- **posthogos-branding**: icons, wallpapers, fonts, Plasma LAF (Light + Dark), color schemes, sound theme, Konsole profile, SDDM theme, Plymouth theme.
- **posthogos-scripts**: `/usr/local/bin/{neohog,papirus-folders,posthogos-firstrun.sh,posthogos-firstrun-rescue.sh,posthogos-snapper-init,posthogos-toolkit-install}` + `/etc/xdg/autostart/posthogos-firstrun.desktop` + the snapper-init and firstrun-rescue systemd units (pre-enabled via vendor `multi-user.target.wants/` symlinks).
- **posthogos-welcome**: Welcome window. Pre-compiled Qt6 launcher binary + bash wrapper + `welcome.qml` + app-menu and autostart `.desktop` entries. The launcher is compiled in the PKGBUILD's `build()` (`g++ -O2 -fPIC` against Qt6Core/Gui/Qml), so no more chroot-time compile.
- **posthogos-config**: `/etc/skel/.zshrc`, `.gitconfig`, ghostty config, zellij config + the `posthogos-dev` layout. KDE/GTK skel files stay in `customize.sh` since `cachyos-kde-settings` already owns those `/etc/skel` paths.
- **posthogos**: meta-package depending on all five above. Lets a fresh Arch install opt into the full stack with `pacman -S posthogos`.

## How a user gets updates

After installing PosthogOS, the live system has `[posthogos]` registered
in `/etc/pacman.conf` (set up by `scripts/posthogos-customize.sh`). A
plain `pacman -Syu` picks up new package versions whenever a new GitHub
release is published.

No first-install dance: the ISO build pacstraps `posthogos-branding`
during `mkarchiso` (Phase 1.5), so every branding file lands on the
installed system with proper pacman ownership from day one. Subsequent
`pacman -Syu` upgrades are clean: no `--overwrite='*'` needed.

## Activation behavior (opt-in on existing Arch)

For PosthogOS users who install via the ISO or have new accounts created
by Calamares, the look-and-feel is active from first login. The relevant
Plasma defaults are in `/etc/skel/.config/` (seeded by `customize.sh`)
and get picked up at user-creation time.

For an existing Arch / CachyOS user who opts in via `pacman -S posthogos`,
the `posthogos-firstrun.sh` autostart entry (fires on every login until
a marker file is written) does the work. After install, one logout +
login cycle is enough to bring up the LAF, color scheme, and wallpaper:
`plasma-apply-lookandfeel`, `plasma-apply-colorscheme`, and
`plasma-apply-wallpaperimage` all apply to the running session.

The one deferred bit is the Kickoff start-button icon and pinned taskbar
launchers: those edits land in `~/.config/plasma-org.kde.plasma.desktop-appletsrc`
during the same firstrun pass but only become visible on the *next*
login (the second logout/login cycle). `refreshCurrentShell` /
`kquitapp+kstart` would apply them live but both tear down the Plasma
shell on QEMU TCG sessions (black-screen), so they're deliberately
skipped. Intentional and self-resolving; no user action needed beyond
the extra logout.

## How a package gets built

Manually, on an Arch host (or in the `posthogos-builder` Docker image):

```bash
cd packages/posthogos-branding
makepkg -d --noconfirm
# → posthogos-branding-<version>-1-any.pkg.tar.zst in cwd
```

`build()` invokes `scripts/build-assets.sh` to populate
`overlay-generated/`; `package()` copies from `overlay/` + `overlay-generated/`
into `$pkgdir`.

`pkgver()` reads from `git describe --tags`, so the package version
tracks the repo tag (e.g. v0.1.0 → 0.1.0).

## How releases flow

```
github release v0.1.0 published
  └─ .github/workflows/build-iso.yml fires
      ├─ scripts/in-container-build.sh
      │   ├─ import POSTHOGOS_PACKAGER_KEY into builder gpg keyring
      │   ├─ for each packages/*/: makepkg --sign → build/posthogos-localrepo/
      │   ├─ repo-add --sign posthogos.db.tar.zst → same dir
      │   ├─ mirror to out/pkgs/
      │   └─ mkarchiso pacstraps posthogos-keyring + posthogos-branding
      │      into the ISO from the file:// local repo (so installed
      │      systems start with pacman-owned + signed files)
      ├─ stamp version + upload ISO to release
      ├─ peaceiris/actions-gh-pages → deploys out/pkgs/ to gh-pages branch
      │   → posthog.github.io/linux-posthogos/x86_64/{posthogos.db,*.pkg.tar.zst,*.sig}
      ├─ scripts/build-deb-packages.sh → out/deb/ (see "Debian/Ubuntu" below)
      ├─ peaceiris/actions-gh-pages → deploys out/deb/ to gh-pages branch
      │   → posthog.github.io/linux-posthogos/deb/{dists,pool,posthogos.gpg}
      └─ attach *.pkg.tar.zst + *.deb to release as backup assets
```

Users on installed systems can `pacman -Syu` (or `apt upgrade`) minutes
after the release publishes.

## Debian / Ubuntu (.deb + apt repo)

`posthogos-branding` and `posthogos-scripts` are portable (plain files,
no pacman-specific machinery), so they're also shipped as `.deb`s for
Debian-based KDE systems. `posthogos-keyring`, `-config`, `-welcome` and
the `posthogos` meta stay Arch-only (keyring trust, `/etc/skel` seeding,
a Qt launcher, and a pacman-repo wiring respectively — none of which map
cleanly to apt).

[`scripts/build-deb-packages.sh`](../scripts/build-deb-packages.sh) does
*not* re-stage files. It repackages the already-built `*.pkg.tar.zst`
(itself just a tar of the staged tree), so the `.deb` payload is
byte-for-byte what Arch ships — one source of truth for the file layout.
The only divergence is Debian's `/usr/bin` policy: the script relocates
PosthogOS's own executables out of `/usr/local/bin` and rewrites the
absolute paths that reference them (leaving `toolkit-install`'s runtime
`op`/`asdf` drops in `/usr/local/bin` alone).

It then assembles a flat apt repo — `pool/` + `dists/stable/main/binary-{amd64,arm64}/`
— and signs `Release` (`InRelease` + `Release.gpg`) with the same PostHog
packager key. The public key is published at `deb/posthogos.gpg` for
`signed-by=`. Without `POSTHOGOS_PACKAGER_KEY` the repo is unsigned
(local dev; apt needs `[trusted=yes]`), mirroring the pacman side.

Both packages are `Architecture: all` (data + shell scripts, nothing
compiled), so a single `_all.deb` serves every arch. apt still resolves
per-arch, though — an arm64 client only reads `binary-arm64/Packages` —
so the same index is published under each `binary-<arch>/` and `Release`
declares both `amd64` and `arm64`. No per-arch build step. (This is
unlike the pacman repo, which is `x86_64`-only because the Arch package
base is.)

Build locally with `bin/build-deb` (runs in a `debian:stable-slim`
container, so it works on macOS too) after `bin/build` has produced
`out/pkgs/`. End users add the repo per the top-level README.

## GPG signing

Every `posthogos-*.pkg.tar.zst` and the `posthogos.db.tar.zst` repo
database are signed with the **PostHog packager key**:

```
fingerprint: 4EBC A8A8 04A5 9A4F 2D56  70AE 5573 6D1E BA43 BEF3
uid:         PostHog Packager <packages@posthog.com>
algorithm:   RSA 4096, sign-only, 2y expiry
```

The public key ships in `posthogos-keyring`, pacstrapped into the ISO
alongside `posthogos-branding`. End-user `/etc/pacman.conf` sets
`SigLevel = Required` for `[posthogos]`.

### One-time human setup

1. Generate the key (already done):
   ```bash
   gpg --quick-generate-key 'PostHog Packager <packages@posthog.com>' rsa4096 sign 2y
   ```
2. Drop the public key file into the keyring package:
   ```bash
   gpg --export packages@posthog.com \
       > packages/posthogos-keyring/posthogos.gpg
   ```
   This file is committed (it's public).
3. Add the secret key to GitHub Actions secrets + the fingerprint to repo variables:
   ```bash
   gpg --armor --export-secret-keys packages@posthog.com \
       | gh secret set POSTHOGOS_PACKAGER_KEY
   gh variable set POSTHOGOS_PACKAGER_KEY_FPR \
       --body 4EBCA8A804A59A4F2D5670AE55736D1EBA43BEF3
   ```
4. Back up `posthogos-packager.sec` somewhere safe and delete the local copy.

### Bootstrap for existing PosthogOS installs

Users on a pre-signing ISO won't have `posthogos-keyring` and will hit
"signature is unknown trust" on first `pacman -Syu` after this lands.
One-time fix:

```bash
# Temporarily trust to install the keyring + branding refresh,
# then SigLevel=Required takes effect for everything after.
sudo pacman -Sy --noconfirm --overwrite='*' \
    --config <(sed 's/SigLevel = Required/SigLevel = Optional TrustAll/' \
                   /etc/pacman.conf) \
    posthogos-keyring posthogos-branding
sudo pacman -Syu  # signature verification now works normally
```

### Local development

`makepkg` runs without `--sign` if `POSTHOGOS_PACKAGER_KEY` is unset, so
local `bin/build` produces unsigned packages and the build-time
`file://` repo (which uses `SigLevel = Optional`) accepts them. CI
hard-fails if `POSTHOGOS_PACKAGER_KEY` is missing, because a release
ISO must be signed.

### Local makepkg signing (developer with key in keyring)

```bash
cd packages/posthogos-branding
makepkg --sign -d --noconfirm
```
