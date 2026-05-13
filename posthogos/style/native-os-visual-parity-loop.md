# Native OS visual parity loop

Status: active goal handoff.

The goal is to make PostHogOS look and feel like the `www.posthog.com` homepage as a native Linux OS. The OS should not embed, launch, or recreate the website. It should apply the same visual language to real KDE/Linux surfaces.

## Non-negotiable target

A screenshot of the booted OS should read as "PostHog made a Linux distro" within 5 seconds.

Judge that by visible screenshots, not by whether the right config files were touched. If the desktop, top panel, file explorer, app launcher, dialogs, or window chrome still read as default CachyOS/KDE, keep iterating.

## Surfaces to compare every pass

- Desktop wallpaper: homepage texture colour, texture density, garden asset placement, empty-space balance.
- Top OS panel/menu bar: fixed at top, full width, light PostHog bar colour, compact height, subtle bottom border, dark icon/text treatment.
- Window chrome: light tertiary titlebar, compact controls, subtle borders, restrained shadow, native behavior intact.
- Dolphin/file explorer: content background, sidebar, toolbar, selected row, hover state, search/input colours, typography.
- App launcher/menu: popup surface, search field, row height, hover/open state, separators, corners, shadow.
- Welcome/dialogs: orange primary action, secondary button, text colour, spacing, border radius, focus state.
- Icons and launchers: real PostHog assets where possible, consistent scale, no cropped logo, no website nav labels.
- Typography: IBM Plex Sans for UI, Source Code Pro for code/terminal where possible, compact website-like sizing.

## Hard guardrails

- Do not add the PostHog website homepage nav items as an OS menu bar.
- Do not use a browser view of PostHog as the desktop.
- Do not use generic grids or hand-drawn substitutes when a real asset exists in `/Users/will/github/posthog.com`.
- Do not call the pass done from config review alone.
- Do not call the pass done from a black VM frame, a rescue-only desktop, or a screenshot set missing Dolphin and the app launcher.

## Required loop

1. Capture a fresh reference screenshot from `https://www.posthog.com/`.
2. Edit the native theme files locally.
3. Hot-apply those changes in the running VM.
4. Capture VM screenshots of the desktop, file explorer, app launcher/menu, and welcome/dialog surfaces.
5. Build a contact sheet next to `reference-posthog-homepage.png`.
6. Review those screenshots against the homepage reference and pick the first visible mismatches a human would notice.
7. Repeat edit, hot-apply, screenshot, and review until the visible surfaces look right.
8. Rebuild the ISO once the hot-applied VM screenshots are good.
9. Boot the rebuilt ISO and capture the same screenshot set as proof that the styling is baked in.
10. If the rebuilt ISO proof regresses from the hot-applied screenshots, patch the theme, hot-apply again, and only then rebuild another ISO.

## Done condition

The loop stops only when Will approves the screenshots or the written self-review can honestly score every surface at least 2 out of 3, with overall impression at 3 out of 3.

The phrase "good enough" means visually good enough in screenshots against the current homepage, not theoretically good enough because a colour token was copied.

## Current loop state

The latest review folder is:

`/Users/will/github/posthogos-live-iso/artifacts/visual-review/20260513-0837-logo-rebuilt-proof`

If context compacts, reopen that folder first. Use `rebuilt-logo-desktop.png` for the latest rebuilt ISO panel proof and `rebuilt-logo-icon-state.txt` for the desktop-entry and icon-resolution state.

The current pass addresses Will's latest logo feedback: PostHog code, GitHub Desktop, Claude Code, Claude Desktop, Codex CLI, and Codex Desktop now use real product logos instead of hand-drawn placeholder badges. This was proven first through hot-applied VM screenshots in `/Users/will/github/posthogos-live-iso/artifacts/visual-review/20260513-0745-logo-hotapply`, then through a rebuilt ISO boot in the latest proof folder. Keep the goal active until Will approves the screenshots.

Logo implementation note: keep the stable `posthogos-*` icon names for pinned launchers, but make the underlying assets real product logos. The task strip renders reliably when those names exist as hicolor icons before the KDE session starts. The hot-apply session needed a display-manager restart after cache rebuild; the rebuilt ISO starts cleanly with the corrected icons.

Current implementation note: the first-run welcome surface should use `qml6 /usr/share/posthogos/welcome/welcome.qml` through `/Users/will/github/posthogos-live-iso/archiso/airootfs/usr/local/bin/posthogos-welcome` and `/Users/will/github/posthogos-live-iso/posthogos/packages/posthogos-branding/pkg/posthogos-branding/usr/local/bin/posthogos-welcome`, with `kdialog` left as the fallback. The Electron prototype is not the primary path because it painted a blank renderer in the VM.

Rejected 2026-05-12 experiment: `org.kde.plasma.kicker` made the launcher compact, but it hid the PostHog-focused app grid and looked more stock. Keep `org.kde.plasma.kickoff` unless a future patch proves a better launcher screenshot in the VM.
