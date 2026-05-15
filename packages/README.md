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

## Phase 1 — branding

Currently shipping:

- **posthogos-branding** — icons, wallpapers, fonts, Plasma LAF (Light + Dark), color schemes, sound theme, Konsole profile, SDDM theme, Plymouth theme.

Planned (Phase 2+):

- **posthogos-scripts** — `/usr/local/bin/posthogos-firstrun.sh`, `neohog`, `posthogos-toolkit-install`, systemd units, autostart entries.
- **posthogos-welcome** — `welcome.qml` + the C++ launcher (pre-compiled in the package; no more chroot-time compile).
- **posthogos-config** — `/etc/skel/*` dotfiles, login banners, ssh banner.
- **posthogos** — meta-package depending on all of the above.

## How a user gets updates

After installing PosthogOS, the live system has `[posthogos]` registered
in `/etc/pacman.conf` (set up by `scripts/posthogos-customize.sh`). A
plain `pacman -Syu` picks up new package versions whenever a new GitHub
release is published.

**First install collision** (one-time): the airootfs that Calamares
copied to disk already contains the icon theme / LAF / etc. files,
owned by no package. When the user first runs `pacman -S
posthogos-branding`, pacman refuses to overwrite those files. Run once:

```bash
sudo pacman -S --overwrite='*' posthogos-branding
```

Subsequent upgrades are clean — pacman now owns the files.

(Phase 1.5 will replace this with: ISO build installs posthogos-branding
via pacstrap so the install starts with pacman-owned files from day
one. Eliminates the collision entirely.)

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
      ├─ build ISO
      ├─ stamp version + upload to release
      ├─ build each packages/*/PKGBUILD
      ├─ repo-add posthogos.db.tar.zst *.pkg.tar.zst
      ├─ peaceiris/actions-gh-pages → deploys to gh-pages branch
      │   → posthog.github.io/linux-posthogos/x86_64/{posthogos.db,*.pkg.tar.zst}
      └─ attach .pkg.tar.zst to release as backup assets
```

Users on installed systems can `pacman -Syu` minutes after the release
publishes.

## TODO — Phase 1.5

- [ ] GPG-sign packages. Generate a PostHog packager key, add to GitHub
      Actions secrets, sign each .pkg.tar.zst with `gpg --detach-sign`,
      drop `TrustAll` from the pacman.conf SigLevel, ship the public key
      in a tiny `posthogos-keyring` package.
- [ ] ISO build installs posthogos-branding via pacstrap rather than
      airootfs copy. Eliminates the first-install file-collision dance.
- [ ] Add posthogos-scripts, posthogos-welcome, posthogos-config,
      posthogos (meta) packages.
- [ ] Add a `posthogos update` wrapper that runs `pacman -Syu` +
      `flatpak update` + any extra channels in one command.

## Signing key generation (when ready for Phase 1.5)

```bash
# On a machine you control. Use a posthog.com email.
gpg --quick-generate-key 'PostHog Packager <packages@posthog.com>' rsa4096 sign 2y

# Export public + secret keys.
gpg --armor --export packages@posthog.com > posthogos-packager.pub
gpg --armor --export-secret-keys packages@posthog.com > posthogos-packager.sec

# Drop posthogos-packager.sec into GitHub Actions secrets as
# POSTHOGOS_PACKAGER_KEY. Ship posthogos-packager.pub in a
# posthogos-keyring package + import via pacman-key in customize.sh.

# Local makepkg signing (after key is in your keyring):
makepkg --sign -d --noconfirm
```
