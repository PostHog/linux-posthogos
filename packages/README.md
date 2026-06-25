# packages/

PosthogOS as a pacman repository — the update path for everything PosthogOS
adds on top of CachyOS (branding, scripts, welcome window, config). Without
it, brand iteration is frozen at whatever ISO each user installed from.

Each `packages/<pkgname>/PKGBUILD` builds a `.pkg.tar.zst` served from
`https://posthog.github.io/linux-posthogos/$arch` (GitHub Pages, `gh-pages`
branch). Installed systems get updates with a plain `pacman -Syu`.

## Packages

- **posthogos-keyring**: PostHog packager GPG public key. Installs the pubring
  and locally signs it via a pacman hook, so `posthogos-*` signatures are
  trusted from first boot. Required for `[posthogos]`'s `SigLevel = Required`.
- **posthogos-branding**: icons, wallpapers, fonts, Plasma LAF (Light + Dark),
  color schemes, sound theme, Konsole profile, SDDM theme, Plymouth theme.
- **posthogos-scripts**: `/usr/local/bin/` tools (neohog, papirus-folders,
  firstrun, snapper-init, toolkit-install, …) + autostart `.desktop` + the
  snapper-init and firstrun-rescue systemd units (pre-enabled via vendor
  `multi-user.target.wants/` symlinks).
- **posthogos-welcome**: Welcome window — Qt6 launcher (compiled in the
  PKGBUILD's `build()`, no chroot-time compile) + bash wrapper + `welcome.qml`
  + app-menu/autostart `.desktop` entries.
- **posthogos-config**: `/etc/skel/.zshrc`, `.gitconfig`, ghostty/zellij
  configs + `posthogos-dev` layout. KDE/GTK skel files stay in `customize.sh`
  (owned by `cachyos-kde-settings`).
- **posthogos**: meta-package depending on all five. `pacman -S posthogos`
  opts a fresh Arch install into the full stack.

## How updates reach users

`scripts/posthogos-customize.sh` registers `[posthogos]` in
`/etc/pacman.conf`, so `pacman -Syu` picks up new releases. The ISO pacstraps
`posthogos-branding` during `mkarchiso` (Phase 1.5), so branding files land
with proper pacman ownership from day one — no first-install dance, no
`--overwrite='*'` on upgrade.

**Activation** — ISO/Calamares users get the look-and-feel from first login
(Plasma defaults seeded into `/etc/skel/.config/` by `customize.sh`). Opt-in
`pacman -S posthogos` users get it via `posthogos-firstrun.sh` (autostart,
fires until a marker file is written); one logout+login applies LAF, color
scheme, and wallpaper live. The Kickoff start-button icon and pinned taskbar
launchers land in the same pass but only appear on the *next* login —
applying them live tears down the Plasma shell on QEMU TCG (black-screen), so
it's deliberately deferred. Self-resolving; no user action beyond the extra
logout.

## Building a package

Manually, on an Arch host (or the `posthogos-builder` Docker image):

```bash
cd packages/posthogos-branding
makepkg -d --noconfirm   # → posthogos-branding-<version>-1-any.pkg.tar.zst
```

`build()` runs `scripts/build-assets.sh` → `overlay-generated/`; `package()`
copies `overlay/` + `overlay-generated/` into `$pkgdir`. `pkgver()` reads
`git describe --tags`, so the version tracks the repo tag.

## How releases flow

A published `github release` fires `.github/workflows/build-iso.yml`:

1. `in-container-build.sh`: import packager key → `makepkg --sign` each
   package → `repo-add --sign` → mirror to `out/pkgs/` → `mkarchiso`
   pacstraps `posthogos-keyring` + `posthogos-branding` from the `file://`
   local repo.
2. `build-deb-packages.sh` → `out/deb/`, `build-rpm-packages.sh` → `out/rpm/`.
3. **One** `gh-pages` commit layering all three repos (pacman `x86_64/`, apt
   `deb/`, dnf `rpm/`) = one Pages deployment.
4. Attach `*.pkg.tar.zst` + `*.deb` + `*.rpm` to the release as backups.

Installed systems can `pacman -Syu` / `apt upgrade` / `dnf upgrade` minutes
after a release publishes.

## .deb + .rpm

`posthogos-branding` and `posthogos-scripts` are portable (plain files), so
they also ship as `.deb`s and `.rpm`s. `-keyring`, `-config`, `-welcome`, and
the meta stay Arch-only (keyring trust, `/etc/skel` seeding, Qt launcher,
pacman wiring — none map cleanly to apt/dnf).

Neither builder re-stages files: both repackage the already-built
`*.pkg.tar.zst` (itself a tar of the staged tree), so the payload is
byte-for-byte what Arch ships — one source of truth. Shared extract/relocate
logic lives in [`scripts/lib/posthogos-pkg.sh`](../scripts/lib/posthogos-pkg.sh):
strips pacman metadata, relocates own executables from `/usr/local/bin` →
`/usr/bin` (leaving `toolkit-install`'s `op`/`asdf` drops alone), and maps
pre-release separators to `~` so betas sort before finals.

- **apt** — [`build-deb-packages.sh`](../scripts/build-deb-packages.sh): flat
  repo (`pool/` + `dists/stable/main/binary-{amd64,arm64}/`) with signed
  `Release`/`InRelease`. Key at `deb/posthogos.gpg`. Local: `bin/build-deb`
  (`debian:stable-slim`, works on macOS).
- **dnf** — [`build-rpm-packages.sh`](../scripts/build-rpm-packages.sh):
  `noarch` rpms via `rpmbuild`, signed, indexed with `createrepo_c`, signed
  `repomd.xml.asc`. Ships `posthogos.repo` + `RPM-GPG-KEY-posthogos`. Local:
  `bin/build-rpm` (`fedora:latest`).

Both are arch-independent — one package serves every arch (dnf handles
`noarch`; apt publishes under both `binary-amd64/` and `binary-arm64/`). The
pacman repo is `x86_64`-only because the Arch base is. Without
`POSTHOGOS_PACKAGER_KEY` both build unsigned for local dev (apt needs
`[trusted=yes]`; dnf `gpgcheck=0`).

## GPG signing

Every `posthogos-*.pkg.tar.zst`, `posthogos.db`, the apt `Release`, and the
rpm `repomd.xml` are signed with the **PostHog packager key**:

```
fingerprint: 4EBC A8A8 04A5 9A4F 2D56  70AE 5573 6D1E BA43 BEF3
uid:         PostHog Packager <packages@posthog.com>
algorithm:   RSA 4096, sign-only, 2y expiry
```

The public key ships in `posthogos-keyring`. Local dev: `makepkg` skips
`--sign` when `POSTHOGOS_PACKAGER_KEY` is unset (build-time `file://` repo is
`SigLevel = Optional`); CI hard-fails if it's missing.

### One-time human setup

```bash
gpg --quick-generate-key 'PostHog Packager <packages@posthog.com>' rsa4096 sign 2y
gpg --export packages@posthog.com > packages/posthogos-keyring/posthogos.gpg  # committed; public
gpg --armor --export-secret-keys packages@posthog.com | gh secret set POSTHOGOS_PACKAGER_KEY
gh variable set POSTHOGOS_PACKAGER_KEY_FPR --body 4EBCA8A804A59A4F2D5670AE55736D1EBA43BEF3
```

Then back up the secret key offline and delete the local copy.

### Bootstrap for pre-signing installs

Users on a pre-signing ISO lack `posthogos-keyring` and hit "signature is
unknown trust" on first `pacman -Syu`. One-time fix:

```bash
sudo pacman -Sy --noconfirm --overwrite='*' \
    --config <(sed 's/SigLevel = Required/SigLevel = Optional TrustAll/' /etc/pacman.conf) \
    posthogos-keyring posthogos-branding
sudo pacman -Syu   # verification works normally afterward
```

### Key rotation & compromise

Trust lists live in `posthogos-keyring` and are read by `pacman-key
--populate`: `posthogos-trusted` (`<fpr>:<owner-trust>:` per line; current
`4EBCA8A8…BEF3:4:`) and `posthogos-revoked` (revoked fingerprints, currently
empty).

**The single-key limit.** Everything is signed by one key, and the only
in-band way to change trust is shipping a new `posthogos-keyring` — itself
signed by the current key. So the channel can *rotate* a key but cannot
*recover from a compromised* one on its own (a thief can sign a keyring that
re-trusts themselves). Compromise recovery needs an **out-of-band** step.

**Routine rotation** (e.g. before expiry) — new keyring must be signed by the
**old** key so trusting systems accept it: generate `NEW_FPR`, replace
`posthogos.gpg`, add `NEW_FPR:4:` to `posthogos-trusted` (keep the old line
during overlap), rotate the CI secret + fpr var, cut a release signed by the
old key, then re-sign with the new key going forward. Once installs have
upgraded, drop the old line, add the old fpr to `posthogos-revoked`, release
again, retire the old key.

**Compromise** — generate a fresh key; publish `NEW_FPR` **out-of-band**
(GitHub over HTTPS, release notes, PostHog comms — this is what users verify
against); revoke the old fpr, trust the new, re-sign *everything*, rotate CI.
End users must not rely on a plain `pacman -Syu` (the attacker can sign
updates too) — instead, out-of-band:

```bash
sudo pacman-key --delete <OLD_FPR>
curl -fsSL -o /tmp/posthogos.gpg \
  https://raw.githubusercontent.com/PostHog/linux-posthogos/main/packages/posthogos-keyring/posthogos.gpg
gpg --show-keys /tmp/posthogos.gpg          # MUST match the announced NEW_FPR
sudo pacman-key --add /tmp/posthogos.gpg
sudo pacman-key --lsign-key <NEW_FPR>
sudo pacman-key --updatedb && sudo pacman -Syu
```

apt/dnf users re-anchor the same way (`/etc/apt/keyrings/posthogos.gpg` via
`signed-by=`; `rpm -e gpg-pubkey-<OLD_KEYID>` + `rpmkeys --import …`) — always
verifying the fingerprint, since all three repos share the `gh-pages` site an
attacker would also control.
