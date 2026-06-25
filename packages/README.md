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
      ├─ scripts/build-deb-packages.sh → out/deb/ (apt repo; see below)
      ├─ scripts/build-rpm-packages.sh → out/rpm/ (dnf repo, in a fedora container)
      ├─ ONE gh-pages commit layering all three repos:
      │   → posthog.github.io/linux-posthogos/x86_64/{posthogos.db,*.pkg.tar.zst,*.sig}
      │   → posthog.github.io/linux-posthogos/deb/{dists,pool,posthogos.gpg}
      │   → posthog.github.io/linux-posthogos/rpm/{repodata,*.rpm,posthogos.repo,RPM-GPG-KEY-posthogos}
      │     (one push = one Pages deployment; see build-iso.yml "Publish repos to gh-pages")
      └─ attach *.pkg.tar.zst + *.deb + *.rpm to release as backup assets
```

Users on installed systems can `pacman -Syu` (or `apt upgrade` / `dnf
upgrade`) minutes after the release publishes.

## Debian/Ubuntu (.deb) + Fedora/openSUSE (.rpm)

`posthogos-branding` and `posthogos-scripts` are portable (plain files,
no pacman-specific machinery), so they're also shipped as `.deb`s and
`.rpm`s. `posthogos-keyring`, `-config`, `-welcome` and the `posthogos`
meta stay Arch-only (keyring trust, `/etc/skel` seeding, a Qt launcher,
and a pacman-repo wiring respectively — none of which map cleanly to
apt/dnf).

Neither builder re-stages files. Both repackage the already-built
`*.pkg.tar.zst` (itself just a tar of the staged tree), so the `.deb` /
`.rpm` payload is byte-for-byte what Arch ships — one source of truth for
the file layout. The shared extract + relocate logic lives in
[`scripts/lib/posthogos-pkg.sh`](../scripts/lib/posthogos-pkg.sh): it
strips pacman metadata and, per Debian/Fedora policy, relocates PosthogOS's
own executables out of `/usr/local/bin` to `/usr/bin`, rewriting the
absolute paths that reference them (leaving `toolkit-install`'s runtime
`op`/`asdf` drops in `/usr/local/bin` alone). The same lib maps pre-release
version separators to `~` so a beta sorts *before* its final release in
both deb and rpm ordering.

- **apt** — [`build-deb-packages.sh`](../scripts/build-deb-packages.sh):
  a flat repo (`pool/` + `dists/stable/main/binary-{amd64,arm64}/`) with a
  signed `Release`/`InRelease`/`Release.gpg`. Public key at `deb/posthogos.gpg`
  for `signed-by=`. Build locally with `bin/build-deb` (runs in
  `debian:stable-slim`, so it works on macOS).
- **dnf** — [`build-rpm-packages.sh`](../scripts/build-rpm-packages.sh):
  `noarch` rpms via `rpmbuild` + a generated spec, signed (`rpm --addsign`),
  indexed with `createrepo_c`, with a signed `repomd.xml.asc`. Ships
  `posthogos.repo` (drop into `/etc/yum.repos.d/`) + `RPM-GPG-KEY-posthogos`.
  Build locally with `bin/build-rpm` (runs in `fedora:latest`).

Both packages are arch-independent (`Architecture: all` / `noarch`: data +
shell scripts), so one package serves every arch. dnf handles `noarch`
transparently; apt resolves per-arch, so the deb index is published under
both `binary-amd64/` and `binary-arm64/` with `Release` declaring both. No
per-arch build step — unlike the pacman repo, which is `x86_64`-only because
the Arch package base is. Without `POSTHOGOS_PACKAGER_KEY` both repos build
unsigned for local dev (apt needs `[trusted=yes]`; dnf `gpgcheck=0`).

## GPG signing

Every `posthogos-*.pkg.tar.zst` and the `posthogos.db.tar.zst` repo
database are signed with the **PostHog packager key**:

```
fingerprint: 4EBC A8A8 04A5 9A4F 2D56  70AE 5573 6D1E BA43 BEF3
uid:         PostHog Packager <linux.posthogos@posthog.com>
algorithm:   RSA 4096, sign-only, 2y expiry
```

> The **fingerprint** is what's actually verified (it's what
> `POSTHOGOS_PACKAGER_KEY_FPR` pins and what `SigLevel`/`gpgcheck` check) —
> always select the key by fingerprint, not email. The uid shown is the
> standard going forward; the currently-deployed key predates the
> `linux.posthogos@posthog.com` standardization, so regenerate it with this
> uid at the next rotation (the `gpg --export <email>` commands below assume
> a freshly-generated key carrying it).

The public key ships in `posthogos-keyring`, pacstrapped into the ISO
alongside `posthogos-branding`. End-user `/etc/pacman.conf` sets
`SigLevel = Required` for `[posthogos]`.

### One-time human setup

1. Generate the key (already done):
   ```bash
   gpg --quick-generate-key 'PostHog Packager <linux.posthogos@posthog.com>' rsa4096 sign 2y
   ```
2. Drop the public key file into the keyring package:
   ```bash
   gpg --export linux.posthogos@posthog.com \
       > packages/posthogos-keyring/posthogos.gpg
   ```
   This file is committed (it's public).
3. Add the secret key to GitHub Actions secrets + the fingerprint to repo variables:
   ```bash
   gpg --armor --export-secret-keys linux.posthogos@posthog.com \
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

### Key rotation & compromise recovery

**The trust model and its limit.** Every `posthogos-*` artifact (pacman
packages + `posthogos.db`, the apt `Release`, the rpm packages + `repomd.xml`)
is signed by the one packager key. The only in-band way to change which key
is trusted is to ship a new `posthogos-keyring` — but that package is itself
signed by the current key. So **the package channel can rotate a key, but it
cannot recover from a *compromised* key on its own**: whoever holds the key
can also sign a "new keyring" that re-trusts themselves. Recovery from
compromise therefore requires an **out-of-band** step (below). This is the
standard keyring-bootstrap weakness, called out here so it isn't a surprise.

The trust lists live in this package:

- `posthogos-trusted` — `<fingerprint>:<owner-trust>:` per line (current:
  `4EBCA8A8…BEF3:4:`, full trust). `pacman-key --populate` reads it.
- `posthogos-revoked` — revoked fingerprints, one per line (currently empty).
  Adding a fingerprint here makes `pacman-key --populate` mark that key
  revoked on the next keyring install/upgrade.

#### Routine rotation (planned — e.g. before the 2028 expiry)

The new keyring must be signed by the **old** key so already-trusting systems
accept the upgrade (noted in the keyring PKGBUILD):

1. Generate the new key; note its fingerprint `NEW_FPR`.
2. In `packages/posthogos-keyring/`: replace `posthogos.gpg` with the new
   public key (`gpg --export NEW_FPR > posthogos.gpg`), and add `NEW_FPR:4:`
   to `posthogos-trusted` (keep the old line during the overlap).
3. Rotate CI: `gh secret set POSTHOGOS_PACKAGER_KEY` (new armored secret key)
   and `gh variable set POSTHOGOS_PACKAGER_KEY_FPR NEW_FPR`.
4. Cut a release **signed by the old key** so current installs trust the
   upgrade, then have it re-sign with the new key going forward.
5. Once telemetry/time says installs have upgraded, drop the old line from
   `posthogos-trusted`, add the old fingerprint to `posthogos-revoked`, and
   cut another release. The old key can then be retired.

#### Compromise response (the key leaked)

Maintainer:

1. **Generate a fresh key immediately** (do not reuse anything derived from
   the old one).
2. **Publish `NEW_FPR` out-of-band** over channels an attacker can't forge:
   the GitHub repo over HTTPS (this README + the committed `posthogos.gpg`),
   the release notes, and any other PostHog comms. This is what users verify
   against — not the package channel.
3. Add the compromised fingerprint to `posthogos-revoked`, add `NEW_FPR:4:`
   to `posthogos-trusted`, replace `posthogos.gpg`, bump the keyring, and
   **sign everything with the new key** (the old key's signatures are now
   suspect — re-sign all packages, `posthogos.db`, the apt `Release`, and the
   rpm `repomd.xml`). Rotate the CI secret + fpr var as above.

End users (out-of-band — do **not** rely on a plain `pacman -Syu`, since the
attacker can sign updates too):

```bash
# 1. Distrust the compromised key.
sudo pacman-key --delete <OLD_FPR>

# 2. Fetch the new public key over HTTPS and VERIFY its fingerprint against
#    the out-of-band announcement before trusting it.
curl -fsSL -o /tmp/posthogos.gpg \
  https://raw.githubusercontent.com/PostHog/linux-posthogos/main/packages/posthogos-keyring/posthogos.gpg
gpg --show-keys /tmp/posthogos.gpg          # must match the announced NEW_FPR
sudo pacman-key --add /tmp/posthogos.gpg
sudo pacman-key --lsign-key <NEW_FPR>
sudo pacman-key --updatedb

# 3. Now updates verify against the new key.
sudo pacman -Syu
```

The same key signs the apt and dnf repos, so those users re-establish trust
out-of-band too:

```bash
# Debian/Ubuntu: replace the keyring referenced by signed-by=
sudo curl -fsSL https://posthog.github.io/linux-posthogos/deb/posthogos.gpg \
  -o /etc/apt/keyrings/posthogos.gpg     # verify fingerprint first

# Fedora/openSUSE: drop the old key, import the new one
sudo rpm -e gpg-pubkey-<OLD_KEYID>       # list with: rpm -q gpg-pubkey --qf '%{NAME}-%{VERSION}\n'
sudo rpmkeys --import https://posthog.github.io/linux-posthogos/rpm/RPM-GPG-KEY-posthogos
```

(Note: the apt/dnf repos are served from the same `gh-pages` site the
attacker would also need to control; the out-of-band fingerprint check is
what actually re-anchors trust in all three cases.)

#### Hardening: a two-tier (offline root) key — recommended, needs setup

The single-key model's weakness (above) is that the *only* channel that can
change trust — the `posthogos-keyring` package — is signed by the same key
that signs packages. Leak that key and the attacker can also ship a keyring
that re-trusts themselves, which is why compromise recovery needs an
out-of-band fingerprint dance. A two-tier model removes that:

- **Root key** — offline / air-gapped, long expiry, **never in CI**. Its only
  jobs: certify the packager key, and sign the `posthogos-keyring` *package*.
- **Packager key** — online (the CI secret, as today), shorter expiry. Signs
  the day-to-day artifacts: the pacman packages + `posthogos.db`, the apt
  `Release`, and the rpm `repomd.xml`.
- `posthogos-trusted` grants **full trust to the root fingerprint only**; the
  packager key is trusted transitively because the root key has certified it.

The payoff: because the keyring package is signed by the **offline** root,
a leaked *packager* key can't push a malicious keyring. Recovery from a
packager-key leak becomes in-band and routine — rotate the packager key,
re-certify it with the offline root, publish a root-signed keyring update —
with no end-user out-of-band step. Only a root-key compromise needs the
out-of-band dance, and the root key lives offline and is touched only at
rotation, so its exposure is minimal.

This is **not wired up in the repo** because it requires real offline key
material and custody decisions that can't (and must not) live in code:

1. Generate the root key on an air-gapped machine; store the secret offline
   (hardware token / paper). Never add it to CI secrets.
2. Certify the packager key with it: `gpg --sign-key <packager-fpr>`.
3. Ship both public keys in `posthogos.gpg`, and set `posthogos-trusted` to
   full-trust the **root** fingerprint (the packager key inherits trust via
   the certification — drop its explicit `:4:` line).
4. Sign the built `posthogos-keyring` package with the root key offline and
   commit/publish that signature; CI keeps signing everything else with the
   packager key.

Adding the `posthogos-trusted` root line before the root key exists would
break `pacman-key --populate` (it can't trust a fingerprint absent from the
pubring), so the repo wiring lands only once the root key is generated. The
code change at that point is small; the work is the key ceremony + custody.

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
