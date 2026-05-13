# Distro GUI manipulation context for PostHogOS

Status: v0.1, awaiting Will review.

This document maps the local CachyOS/PostHogOS ISO tree to the native Linux GUI styling surfaces. It answers: where would we apply the style changes, what APIs or config files control them, and which files should be treated as source of truth.

## Source of truth

The current repo has 2 related layers:

| Layer | Path | Role |
| --- | --- | --- |
| ISO root tree | `/Users/will/github/posthogos-live-iso/archiso/airootfs` | Files copied into the live ISO filesystem. Fastest place to see what the booted system receives. |
| Branding package | `/Users/will/github/posthogos-live-iso/posthogos/packages/posthogos-branding` | Arch package that bundles identity, KDE defaults, wallpaper, Plasma theme, icons, launchers, and welcome scripts. |

The current ISO pass delivers GUI branding through the `archiso/airootfs` overlay plus the KDE defaults hook. `posthogos-branding` still exists as a local package build artifact, but it is not in `archiso/packages_desktop.x86_64` right now because it owns the same paths as the overlay and collides with `cachyos-kde-settings` on KDE defaults. For durable changes in this pass, update the matching file in `archiso/airootfs`, rebuild the ISO, then verify in the VM.

Avoid treating `posthogos/packages/posthogos-branding/pkg/posthogos-branding` as hand-authored source. It is package output, although it is useful for checking what the package currently contains.

## Packaging path

The GUI branding source files currently live in `archiso/airootfs`, with `posthogos-branding` kept as the package-shaped bundle for future cleanup.

Relevant package metadata:

- Package name and purpose: `/Users/will/github/posthogos-live-iso/posthogos/packages/posthogos-branding/PKGBUILD:2`
- Runtime GUI dependencies: `/Users/will/github/posthogos-live-iso/posthogos/packages/posthogos-branding/PKGBUILD:9`
- Files copied into the package: `/Users/will/github/posthogos-live-iso/posthogos/packages/posthogos-branding/PKGBUILD:25`

The branded source tree includes:

- OS identity: `etc/os-release`, `etc/hostname`, `etc/cachyos-release`
- KDE user defaults under `usr/share/posthogos/branding/etc/skel/.config`
- Plasma desktop theme under `usr/share/plasma/desktoptheme/posthogos`
- Wallpaper under `usr/share/wallpapers/PostHogOS`
- Launchers under `usr/share/applications`
- App icons under `usr/share/icons/hicolor/scalable/apps`
- Native helper scripts under `usr/local/bin`

## KDE default seeding

KDE settings have 3 application points.

| Application point | File | What it does |
| --- | --- | --- |
| Package hook | `/Users/will/github/posthogos-live-iso/archiso/airootfs/etc/pacman.d/hooks/zzzz80-posthogos-kde-defaults.hook` | Runs after `cachyos-kde-settings` is installed or upgraded. |
| Seeder script | `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/apply-kde-defaults` | Copies the branded KDE config templates into `/etc/skel/.config` and hides CachyOS Hello. |
| Runtime live-user script | `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-live-setup` | Re-applies wallpaper, panel placement, font, accent, theme, and Docker/user setup after the live user session starts. |
| Live session rescue | `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-live-session-rescue` | Runs from a non-blocking systemd service after the display manager, waits for KWin's real session bus, starts `plasmashell` only after KWin exists if KDE stalls before Shell, then runs the live setup with bounded timeouts on that session bus. It supports both `kwin_x11` and `kwin_wayland`. |
| Boot service autostarts | `/Users/will/github/posthogos-live-iso/archiso/airootfs/etc/systemd/system/multi-user.target.wants/` | Keep heavyweight developer services installed but not autostarted during the first visual pass. Do not enable `pacman-init.service` or `docker.service` here unless the VM desktop has already proven stable. |

Source details:

- The hook targets `cachyos-kde-settings`: `/Users/will/github/posthogos-live-iso/archiso/airootfs/etc/pacman.d/hooks/zzzz80-posthogos-kde-defaults.hook:2`
- The hook executes the seeder script: `/Users/will/github/posthogos-live-iso/archiso/airootfs/etc/pacman.d/hooks/zzzz80-posthogos-kde-defaults.hook:13`
- The seeder script copies `kdeglobals`, `plasma-org.kde.plasma.desktop-appletsrc`, `plasmarc`, and `plasmashellrc`: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/apply-kde-defaults:7`
- The live-user script uses `kwriteconfig6`: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-live-setup:20`
- The live-user script uses `plasma-apply-wallpaperimage`: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-live-setup:39`
- The live-user script uses `qdbus6 org.kde.PlasmaShell.evaluateScript`: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-live-setup:43`

Practical rule: edit the template files first, then mirror anything session-critical into `posthogos-live-setup` so the already-created live user gets the same result.

## KDE config files

### `kdeglobals`

Path:

`/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/kdeglobals`

Controls:

- Global accent colour: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/kdeglobals:2`
- General font, menu font, toolbar font, and monospace font: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/kdeglobals:7`
- Button palette: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/kdeglobals:13`
- Selection palette: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/kdeglobals:41`
- View palette: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/kdeglobals:69`
- Window palette: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/kdeglobals:83`
- Icon theme, look-and-feel package, and widget style: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/kdeglobals:97`
- Window manager titlebar colours: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/kdeglobals:105`

Use this for:

- IBM Plex Sans defaults.
- PostHog light palette for Qt/KDE apps.
- Selection, link, hover, and focus colours.
- Titlebar active/inactive colours when Breeze window decorations are still in use.

Important: `kdeglobals` can name a colour scheme, but KDE apps need that scheme to exist as a loadable file too. Keep `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/color-schemes/PostHogOS.colors` in sync with the colour sections in this file, and make sure runtime scripts write `ColorScheme=PostHogOS`, not `BreezeLight`.

### `plasmarc`

Path:

`/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasmarc`

Controls:

- Plasma desktop theme name: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasmarc:1`
- User wallpaper list: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasmarc:4`

Use this for selecting the `posthogos` Plasma shell theme.

### `plasmashellrc`

Path:

`/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasmashellrc`

Controls:

- Default panel floating state: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasmashellrc:1`
- Default panel thickness: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasmashellrc:3`

Use this to keep the panel fixed and compact.

### `plasma-org.kde.plasma.desktop-appletsrc`

Path:

`/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc`

Controls:

- Desktop containment plugin and image wallpaper plugin: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc:4`
- Wallpaper file and preview: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc:13`
- Panel containment and top location: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc:17`
- Panel geometry, full-width mode, fixed visibility, and 44px height: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc:24`
- Panel widgets: Kickoff launcher, icon task manager, margins separator, system tray, digital clock: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc:32`

Use this for:

- Top panel location.
- Full-width fixed panel.
- Panel height.
- Which native widgets appear in the panel.
- Wallpaper plugin and image path.

KDE panel location uses numeric config in the template and string config in the runtime DBus script. The runtime script currently sets `panel.location = "top"` at `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-live-setup:53`.

## VM-compatible Plasma session

The first visual proof pass runs under QEMU, so the live image should prefer the most predictable VM display path.

Current choice:

- Install `plasma-x11-session` and `xorg-server` in `/Users/will/github/posthogos-live-iso/archiso/packages_desktop.x86_64`.
- Set `/Users/will/github/posthogos-live-iso/archiso/airootfs/etc/plasmalogin.conf` and `/Users/will/github/posthogos-live-iso/archiso/airootfs/etc/plasmalogin.conf.d/autologin.conf` to `Session=plasmax11.desktop`.
- Keep the rescue script compatible with both `kwin_x11` and `kwin_wayland`, because installed systems may still choose Wayland later.

Reason: the 2026-05-12 VM pass autologged into the Wayland session, started `kwin_wayland`, `plasmashell`, `kded6`, and `ksmserver`, but QEMU still screendumped a black frame. The same ISO also lacked `/usr/bin/kwin_x11`, `/usr/bin/Xorg`, and a populated `/usr/share/xsessions`, so it had no X11 fallback path.

Do not score the PostHog visual match from a black Wayland frame. Fix the native display path first, then run the screenshot review loop.

## Live boot blockers

The visual loop should reach the desktop fast enough that the first screenshot is meaningful.

Current boot-blocking mitigations:

- `NetworkManager-wait-online.service.d/override.conf` exits immediately.
- `systemd-networkd-wait-online.service.d/override.conf` exits immediately.
- `ldconfig.service.d/override.conf` exits immediately in the live image.
- `plasma-ksplash.service.d/override.conf` exits immediately for the live user.

Reason: the 2026-05-12 VM pass spent about 2 minutes waiting for network-online and about 4 minutes rebuilding the dynamic linker cache before the login manager could start. These checks are bad first-impression blockers for a live developer ISO and do not help the visual proof loop.

## Plasma desktop theme

Path:

`/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/plasma/desktoptheme/posthogos`

Files:

| File | Role |
| --- | --- |
| `metadata.json` | Registers the theme as `posthogos` with Plasma. |
| `metadata.desktop` | Legacy metadata for the same theme. |
| `colors` | Plasma shell colour scheme. |
| `widgets/panel-background.svg` | Normal panel background SVG. |
| `opaque/widgets/panel-background.svg` | Opaque panel background SVG. Keep in sync with normal panel background. |

Source details:

- Theme id and name live in `metadata.json`: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/plasma/desktoptheme/posthogos/metadata.json:10`
- Plasma theme colour scheme starts at `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/plasma/desktoptheme/posthogos/colors:1`
- Panel background SVG sets fill `#e4e3d8` and bottom edge `#bfc1b7`: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/plasma/desktoptheme/posthogos/widgets/panel-background.svg:3`
- Plasma expects named SVG elements such as `center`, `top`, `bottom`, `left`, `right`, corners, and `north-*` variants: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/plasma/desktoptheme/posthogos/widgets/panel-background.svg:9`

Use this for:

- Panel fill and border.
- Plasma shell widgets, panel widgets, and popup colours.
- Theme-level shell surface colours that `kdeglobals` does not fully cover.

Likely next expansion: add SVGs for more Plasma widgets if the VM still shows default Breeze surfaces. Candidate theme assets include dialog backgrounds, tooltip backgrounds, button assets, task items, and Kickoff launcher pieces.

## KDE colour scheme

Path:

`/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/color-schemes/PostHogOS.colors`

Controls:

- The named Qt/KDE app colour scheme loaded by `ColorScheme=PostHogOS`.
- Dolphin, `kdialog`, System Settings, and other native app colours where Breeze widget style is still used.
- Selection/default-button colours that otherwise fall back to Breeze blue.

Use this for native app surfaces. If Dolphin or `kdialog` looks like stock Breeze in VM screenshots, check this file and `posthogos-live-setup` before adding deeper custom UI code.

## Wallpaper

Path:

`/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/wallpapers/PostHogOS`

Files:

| File | Role |
| --- | --- |
| `metadata.json` | Registers the wallpaper package. |
| `contents/images/3840x2160.png` | Actual wallpaper applied by KDE. |
| `contents/images/source-assets/keyboard_garden_bg_light.png` | Vendored PostHog website texture source. |
| `contents/images/source-assets/keyboard_garden_light.png` | Vendored PostHog website garden illustration source. |
| `contents/images/source-assets/posthog-logomark.svg` | Vendored PostHog logo asset. |

Source details:

- Wallpaper metadata id/name: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/wallpapers/PostHogOS/metadata.json:1`
- The active config points KDE to `3840x2160.png`: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/branding/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc:13`
- The runtime script reapplies the same file with `plasma-apply-wallpaperimage`: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-live-setup:39`
- The wallpaper generator uses the website keyboard-garden base colour `#E1D7C2`: `/Users/will/github/posthogos-live-iso/posthogos/render-wallpaper.py:14`

Use this for:

- Final composed desktop wallpaper.
- Boot splash reuse if we want one source image adapted to several sizes.

Implementation note: KDE’s image wallpaper wants a single image here. The PostHog website uses layered texture plus illustration; in the distro we should generate the final composed PNG from the vendored source assets, then set KDE to that PNG.

Current colour-match note: the 2026-05-12 feedback pass corrected the wallpaper base from `#eeefe9` to the website keyboard-garden base `#E1D7C2`, sourced from `/Users/will/github/posthog.com/src/hooks/useTheme.tsx:24`.

## Welcome and launcher flow

Paths:

- `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-welcome`
- `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications/posthogos-welcome.desktop`
- `/Users/will/github/posthogos-live-iso/archiso/airootfs/etc/xdg/autostart/posthogos-welcome.desktop`

Current implementation:

- Uses a native `kdialog --menu` first-run launcher so the welcome surface inherits the KDE/PostHogOS theme and stays reliable in the VM.
- The menu opens native apps, folders, terminals, CLI entrypoints, Docker Desktop, GitHub Desktop, and PostHog docs from `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-welcome`.
- The older Electron welcome source files still live in `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/posthogos/welcome`, but they are not the primary launch path because the VM rendered a blank white Electron window during the 2026-05-12 visual pass.
- Keep future welcome work native unless Will explicitly asks for a custom shell. The acceptance target is a themed Linux OS surface, not a web-app surface.

Use this for:

- The native first-run launcher.
- Proof that PostHog code, Cursor, Claude, Codex, GitHub Desktop, Docker Desktop, and terminal flows are present.

Styling constraint: the Electron window has better control over PostHog-style spacing, buttons, menu rows, and typography than `kdialog`. Keep the fallback for rescue/debug only, but review the Electron welcome window in screenshots for the real visual pass.

## Application launchers and icons

Paths:

- Launchers: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications/posthogos-*.desktop`
- Scalable app icons: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/icons/hicolor/scalable/apps/posthogos-*.svg`
- Folder/place icons: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/icons/posthogos/128x128/places`
- Folder mimetype icons: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/icons/posthogos/128x128/mimetypes`
- Fallback pixmap: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/pixmaps/posthogos.svg`

Current launchers:

- Claude Code: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications/posthogos-claude-code.desktop:1`
- Claude Desktop: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications/posthogos-claude-desktop.desktop:1`
- Codex CLI: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications/posthogos-codex-cli.desktop:1`
- Codex desktop launcher: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications/posthogos-codex-desktop.desktop:1`
- Cursor with PostHog: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications/posthogos-cursor.desktop:1`
- Docker Desktop: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications/posthogos-docker-desktop.desktop:1`
- GitHub Desktop: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications/posthogos-github-desktop.desktop:1`
- PostHog code: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications/posthogos-posthog-code.desktop:1`
- PostHogOS welcome: `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications/posthogos-welcome.desktop:1`

Use this for:

- App menu entries.
- Desktop shortcuts if we choose to place any.
- Icon/source asset replacement.

Current folder icon note: Dolphin folder icons now use the real website folder asset referenced at `/Users/will/github/posthog.com/src/components/OSIcons/AppIcon.tsx:22`, vendored into the KDE icon theme as `128x128` PNG aliases so native folder views pick it up.

## Login, splash, and boot visuals

Current files:

- KDE splash config: `/Users/will/github/posthogos-live-iso/archiso/airootfs/etc/skel/.config/ksplashrc`
- Plasma login autologin: `/Users/will/github/posthogos-live-iso/archiso/airootfs/etc/plasmalogin.conf`
- GRUB splash image: `/Users/will/github/posthogos-live-iso/archiso/grub/splash.png`
- Syslinux splash images: `/Users/will/github/posthogos-live-iso/archiso/syslinux/splash.png` and `/Users/will/github/posthogos-live-iso/archiso/syslinux/splash1.png`

Source details:

- `ksplashrc` currently uses Breeze: `/Users/will/github/posthogos-live-iso/archiso/airootfs/etc/skel/.config/ksplashrc:1`
- `plasmalogin.conf` autologins `liveuser` into Plasma: `/Users/will/github/posthogos-live-iso/archiso/airootfs/etc/plasmalogin.conf:1`
- Existing boot splash image sizes are 1920x1080, 1920x1080, and 640x480.

Use this for:

- Branded bootloader screens.
- KDE splash defaults.
- Login/autologin surface constraints.

Likely next expansion: determine whether this image uses `plasmalogin` only or also has a packaged SDDM theme path in the CachyOS base. Current local `airootfs` only shows `plasmalogin` config.

## Runtime APIs

These are the native APIs/scripts already used in the distro tree.

| API/tool | Current use | File |
| --- | --- | --- |
| `kwriteconfig6` | Writes KDE config keys for font, accent, theme, panel settings. | `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-live-setup:20` |
| `plasma-apply-wallpaperimage` | Applies the wallpaper file to the live Plasma session. | `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-live-setup:39` |
| `qdbus6 org.kde.PlasmaShell.evaluateScript` | Runs JavaScript against Plasma Shell to set desktop wallpaper and panel layout. | `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-live-setup:43` |
| Electron | Native welcome shell with local PostHog-styled HTML. | `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-welcome:6` |
| `kdialog` | Fallback native welcome menu if Electron is unavailable. | `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-welcome:11` |
| `.desktop` files | Registers app menu entries and launch commands. | `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/applications` |
| Plasma theme SVG asset names | Skins panel and Plasma shell surfaces. | `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/share/plasma/desktoptheme/posthogos/widgets/panel-background.svg:9` |

## Change order for the next styling pass

1. Update colour and font tokens in `kdeglobals`, `/usr/share/color-schemes/PostHogOS.colors`, and the Plasma theme `colors`.
2. Update panel geometry and containment in `plasma-org.kde.plasma.desktop-appletsrc`, `plasmashellrc`, and matching `posthogos-live-setup` runtime calls.
3. Update `panel-background.svg` and `opaque/widgets/panel-background.svg` together.
4. Regenerate `3840x2160.png` wallpaper from vendored PostHog source assets.
5. Replace PostHog-specific launcher icons with source-backed assets or refined native SVGs.
6. Review the Electron welcome flow against the homepage screenshot and keep `kdialog` only as fallback.
7. Rebuild `posthogos-branding`, rebuild the ISO, boot in VM, and capture screenshots.

## Open review questions

1. Is this enough distro-side context, or do you want a deeper KDE theme asset map for launcher popups, task items, tooltips, and dialogs?
2. Should the next pass keep using Breeze window decorations plus `kdeglobals`, or should it create a custom Aurorae/KWin decoration for more PostHog-like titlebars?
3. Should the welcome app grow into a Qt/QML native app later, or is the local Electron shell acceptable because the ISO already includes Electron-based desktop tooling?
