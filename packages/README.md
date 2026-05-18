# packages/

PosthogOS as a pacman repository.

## What and why

Everything PosthogOS adds on top of CachyOS — icons, wallpapers, Plasma
look-and-feel, fonts, scripts, the welcome window — needs an update
path. Without one, brand iteration is frozen at whatever ISO each user
installed from.

The pacman repo hosted at `https://posthog.github.io/linux-posthogos/$arch`
(GitHub Pages from this repo's `gh-pages` branch) closes that gap. Each
`packages/<pkgname>/PKGBUILD` produces a `.pkg.tar.zst` that an installed
PosthogOS can `pacman -Syu` to receive.

## Currently shipping

- **posthogos-keyring** — the PostHog packager GPG public key. Installs the
  pubring at `/usr/share/pacman/keyrings/posthogos.gpg` and locally signs
  it into `/etc/pacman.d/gnupg/` via a pacman hook, so the system trusts
  every `posthogos-*` signature from first boot. Required for the
  end-user `[posthogos]` repo's `SigLevel = Required`.
- **posthogos-branding** — icons, wallpapers, fonts, Plasma LAF (Light + Dark), color schemes, sound theme, Konsole profile, SDDM theme, Plymouth theme.
- **posthogos-scripts** — `/usr/local/bin/{neohog,papirus-folders,posthogos-firstrun.sh,posthogos-firstrun-rescue.sh,posthogos-snapper-init,posthogos-toolkit-install}` + `/etc/xdg/autostart/posthogos-firstrun.desktop` + the snapper-init and firstrun-rescue systemd units (pre-enabled via vendor `multi-user.target.wants/` symlinks).
- **posthogos-welcome** — Welcome window: pre-compiled Qt6 launcher binary + bash wrapper + `welcome.qml` + app-menu and autostart `.desktop` entries. The launcher is compiled in the PKGBUILD's `build()` (`g++ -O2 -fPIC` against Qt6Core/Gui/Qml), so no more chroot-time compile.
- **posthogos-config** — `/etc/skel/.zshrc`, `.gitconfig`, ghostty config, zellij config + the `posthogos-dev` layout. KDE/GTK skel files stay in `customize.sh` since `cachyos-kde-settings` already owns those `/etc/skel` paths.
- **posthogos** — Meta-package depending on all five above. Lets a fresh Arch install opt into the full stack with `pacman -S posthogos`.

## How a user gets updates

After installing PosthogOS, the live system has `[posthogos]` registered
in `/etc/pacman.conf` (set up by `scripts/posthogos-customize.sh`). A
plain `pacman -Syu` picks up new package versions whenever a new GitHub
release is published.

No first-install dance: the ISO build pacstraps `posthogos-branding`
during `mkarchiso` (Phase 1.5), so every branding file lands on the
installed system with proper pacman ownership from day one. Subsequent
`pacman -Syu` upgrades are clean — no `--overwrite='*'` needed.

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
      └─ attach .pkg.tar.zst to release as backup assets
```

Users on installed systems can `pacman -Syu` minutes after the release
publishes.

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
`file://` repo (which uses `SigLevel = Optional TrustAll`) accepts them.
CI hard-fails if `POSTHOGOS_PACKAGER_KEY` is missing — a release ISO
must be signed.

### Local makepkg signing (developer with key in keyring)

```bash
cd packages/posthogos-branding
makepkg --sign -d --noconfirm
```

## Status

Phase 1.5 is code-complete:

- [x] ISO build installs posthogos-branding via pacstrap rather than
      airootfs copy. Eliminates the first-install file-collision dance.
- [x] GPG-sign packages (posthogos-keyring + `makepkg --sign` /
      `repo-add --sign` in CI).

Before the first signed release, the human steps in
[One-time human setup](#one-time-human-setup) above need to run once.

Phase 2 (complete):

- [x] `posthogos-scripts` — `/usr/local/bin/posthogos-firstrun.sh`,
      `neohog`, `posthogos-toolkit-install`, systemd units, autostart entry.
- [x] `posthogos-welcome` — `welcome.qml` + the C++ launcher (pre-compiled
      in the package; no more chroot-time compile).
- [x] `posthogos-config` — `/etc/skel/*` dotfiles (`.zshrc`, `.gitconfig`,
      ghostty + zellij configs).
- [x] `posthogos` — meta-package depending on all of the above.
