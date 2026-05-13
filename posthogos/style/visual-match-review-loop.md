# Visual match review loop

Status: v0.1, awaiting Will review.

This is the acceptance loop for PostHogOS styling. The high-level goal is simple: the native Linux OS should visibly feel like the PostHog homepage when someone opens the desktop, panel menus, file explorer, dialogs, app launcher, and first-run flows.

The OS stays native Linux. The visual target is the PostHog website’s theme, materials, spacing, colour, typography, chrome, and asset language.

## Reference target

Primary reference:

- Live homepage: `https://www.posthog.com/`, which currently redirects to `https://posthog.com/`
- Local source repo: `/Users/will/github/posthog.com`

The live homepage is the visual reference for screenshots. The local source repo is the authority for assets, theme tokens, and implementation details.

## Review artifacts

Every visual pass should create a timestamped folder:

`/Users/will/github/posthogos-live-iso/artifacts/visual-review/YYYYMMDD-HHMM/`

Required files:

| File | Purpose |
| --- | --- |
| `reference-posthog-homepage.png` | Fresh screenshot of the live PostHog homepage. |
| `vm-desktop.png` | Fresh screenshot of the booted PostHogOS desktop. |
| `vm-file-explorer.png` | Dolphin/file explorer open, showing native window chrome and content surfaces. |
| `vm-app-launcher.png` | KDE app launcher/menu open. |
| `vm-dialog-or-welcome.png` | Welcome flow or representative native dialog open. |
| `contact-sheet.png` | Side-by-side comparison of reference and OS screenshots. |
| `self-review.md` | Written visual review with gaps, fixes, and next pass decisions. |

Optional files:

- `vm-panel-menu.png`
- `vm-terminal.png`
- `vm-settings.png`
- `vm-software-screen.png`

## Capture rules

Use the same viewport class for comparison where practical.

- Desktop reference screenshot: around `1728x1037` or similar wide desktop.
- VM screenshot: match the same aspect ratio where practical.
- Capture the top panel, desktop background, at least 1 native window, and at least 1 open menu/dialog.
- Use the live PostHog homepage for the visual screenshot reference, then use local `posthog.com` source files to explain which token or asset caused the target look.

## Visual review checklist

Score each area from 0 to 3.

| Score | Meaning |
| --- | --- |
| 0 | Visibly off. A normal viewer would say it belongs to another design system. |
| 1 | Some PostHog colours/assets appear, but the surface still reads as default Linux/KDE. |
| 2 | Mostly PostHog-like. Remaining gaps are small or constrained by native toolkit limits. |
| 3 | Strong match. It reads as a native OS version of the PostHog homepage theme. |

Areas to score:

1. Desktop background: texture colour, density, garden asset placement, empty-space balance.
2. Top panel/menu bar: location, height, colour, border, icon/text colour, active task treatment.
3. Window chrome: titlebar colour, border, radius, shadow, controls, active/inactive state.
4. File explorer: content background, sidebar, row hover, selected item, toolbar/menu styling.
5. App launcher/menu: popup background, search field, menu rows, hover state, separator, shadow.
6. Dialogs/welcome: buttons, typography, spacing, borders, primary action treatment.
7. Icons and launchers: PostHog-specific icons, label typography, scale, spacing.
8. Typography: IBM Plex Sans usage, size, weight, text colour, density.
9. Accent states: orange buttons, blue focus/selection, warning/error/success colours.
10. Overall impression: first 5-second visual read against the homepage.

## Acceptance bar

A styling pass can be called visually acceptable only when:

- Every checklist area scores at least 2.
- Overall impression scores 3.
- The top panel is fixed to the top, full width, and visually tied to the homepage bar colour.
- Opening Dolphin/file explorer still feels themed, not like untouched Breeze.
- Opening the app launcher or a menu still feels themed, not like untouched Breeze.
- The wallpaper uses the real PostHog source-referenced keyboard garden assets.
- The self-review lists any remaining toolkit constraints honestly.
- Will approves the screenshots or explicitly says the match is close enough.

## Loop

Repeat this loop until the acceptance bar is met:

1. Capture `reference-posthog-homepage.png` from the live homepage.
2. Boot the current ISO in a VM.
3. Capture the required VM screenshots.
4. Build `contact-sheet.png`.
5. Write `self-review.md` with checklist scores and visible gaps.
6. Pick the smallest set of changes likely to move the lowest scores.
7. Apply changes to the documented style surfaces:
   - `kdeglobals`
   - `/usr/share/color-schemes/PostHogOS.colors`
   - `plasmarc`
   - `plasmashellrc`
   - `plasma-org.kde.plasma.desktop-appletsrc`
   - Plasma desktop theme files
   - wallpaper source/composition
   - launcher icons
   - welcome/dialog implementation
8. Rebuild `posthogos-branding` if package-owned files changed.
9. Rebuild the ISO.
10. Boot the ISO again and repeat.

## Eye-match guardrail

The loop is allowed to keep running even when the implementation is technically correct. The approval target is visible similarity to the current PostHog homepage at normal screenshot scale.

For every pass, compare the screenshots as a viewer would, then list the first 3 things that feel visually off before reading code. Prioritize fixes in this order:

1. Global first read: background, top panel, major illustration placement, overall colour temperature.
2. Native daily surfaces: file explorer, app launcher/menu, welcome flow, dialogs, terminal, settings.
3. Detail polish: icon aliases, hover states, button shadows, row selection, titlebars, font weight.

Stop only when the OS screenshots would plausibly be described as a native Linux version of the PostHog website theme, or when Will approves the current pass.

This loop is deliberately screenshot-led. KDE config, Plasma theme files, colour schemes, and packaged assets are implementation details. If screenshots disagree with the intended theme, the screenshots win and the next pass should patch the visible mismatch.

## Self-review format

Create `self-review.md` with this structure:

```md
# Visual review: YYYY-MM-DD HH:MM

## Reference

- Live homepage screenshot: reference-posthog-homepage.png
- VM screenshots: vm-desktop.png, vm-file-explorer.png, vm-app-launcher.png, vm-dialog-or-welcome.png

## Scores

| Area | Score | Notes |
| --- | ---: | --- |
| Desktop background | 0-3 | ... |
| Top panel/menu bar | 0-3 | ... |
| Window chrome | 0-3 | ... |
| File explorer | 0-3 | ... |
| App launcher/menu | 0-3 | ... |
| Dialogs/welcome | 0-3 | ... |
| Icons and launchers | 0-3 | ... |
| Typography | 0-3 | ... |
| Accent states | 0-3 | ... |
| Overall impression | 0-3 | ... |

## Visible gaps

- ...

## Next fixes

1. ...
2. ...
3. ...

## Constraints

- ...

## Done call

Approved by Will: yes/no
```

## High-salience mismatch examples

These should trigger another styling pass:

- Panel floats, sits at the bottom, has rounded screen-edge corners, or uses default dark Plasma material.
- Wallpaper reads as a generic grid or a custom drawing rather than the PostHog keyboard garden.
- File explorer opens with default Breeze blue selection and default grey titlebar.
- App launcher opens with default KDE dark/light styling and no PostHog material match.
- Dialog primary buttons use default KDE styling instead of PostHog orange button treatment.
- Fonts fall back to KDE defaults instead of IBM Plex Sans.
- PostHog logo or logomark appears cropped, distorted, or too small to read.
