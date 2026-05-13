# PostHogOS build goal

Build a real CachyOS-based PostHogOS ISO through a staged, source-backed styling workflow. The website prototype and post-boot VM package install paths are out of scope.

## Current goal

1. Get context from the local `/Users/will/github/posthog.com` source repo and build a detailed PostHog website style document. Iterate until Will says the style doc is detailed enough.
2. Use the already-local distro tree, inspect how the Linux GUI styling is wired, and build a context document for how to manipulate it safely. Iterate until Will says the distro GUI context is detailed enough.
3. Apply the approved style docs to the Linux distro GUI.
4. Capture a fresh live PostHog homepage screenshot and fresh VM screenshots of the OS desktop, file explorer, app launcher/menu, and welcome/dialog surfaces.
5. Self-review those screenshots against the homepage reference, apply fixes, rebuild, boot, and repeat until the OS visibly matches the PostHog website theme closely enough for Will to approve.

## Approval gates

- Do not continue to broad implementation from screenshot vibes.
- Finish and review `posthogos/style/posthog-website-style-source.md` before doing the distro GUI manipulation doc.
- Finish and review `posthogos/style/distro-gui-manipulation-context.md` before applying another full styling pass.
- Use `posthogos/style/visual-match-review-loop.md` for every styling pass after the docs are approved.
- Do not call the styling pass done without a live homepage reference screenshot, VM screenshots, contact sheet, and written self-review.
- Every visual decision should point to either PostHog source evidence or distro/KDE source evidence.

## Visual match goal

PostHogOS should look and feel like a native Linux OS version of the PostHog homepage. The high-salience surfaces are the top menu bar/panel, desktop wallpaper, file explorer, app launcher/menu, window chrome, dialogs, buttons, icons, fonts, and first-run welcome flow.

The comparison target is the visible live homepage at `https://www.posthog.com/`, with local implementation evidence from `/Users/will/github/posthog.com`.

Repeat screenshot capture, self-review, fixes, hot-apply in the running VM, ISO rebuild, and VM boot until the visible match is good enough for Will.

The visual loop is an explicit goal section, not a one-off QA task. If a future context compaction happens, continue from the latest `artifacts/visual-review/*/self-review.md`, fix the lowest-scoring visible surfaces, rebuild, boot, and capture the next pass before calling the styling done.

## Native visual parity loop

Use `posthogos/style/native-os-visual-parity-loop.md` as the short handoff doc for this goal.

The acceptance standard is visible-eye similarity, not config completeness. A pass only counts when screenshots of the real VM desktop, Dolphin/file explorer, app launcher/menu, and welcome/dialog surfaces look like native Linux equivalents of the current `www.posthog.com` homepage theme.

If the OS opens a native surface and a normal viewer would still call it stock KDE, keep looping. Capture screenshots, compare against the live homepage reference, write the visual gaps, patch the lowest-scoring surfaces, hot-apply them in the running VM, capture again, then rebuild the ISO only after the hot-applied screenshots look right.

## Latest visual pass

Latest hot-apply review folder: `/Users/will/github/posthogos-live-iso/artifacts/visual-review/20260512-2201-live-hotapply-panel-clock`.

Latest rebuilt ISO proof folder: `/Users/will/github/posthogos-live-iso/artifacts/visual-review/20260513-0837-logo-rebuilt-proof`.

Latest verdict: the latest logo pass was hot-applied first, then the ISO was rebuilt and booted fresh. The top OS panel now shows real program logos for PostHog code, Claude Code, Codex, GitHub Desktop, Docker, Cursor, and file explorer. PostHog code uses the PostHog logomark, GitHub uses the GitHub Desktop icon from the packaged app, Claude Code and Claude Desktop use the Claude app icon from the packaged app, and Codex CLI/Desktop use the Codex Desktop icon from the packaged app.

Latest evidence: `rebuilt-logo-desktop.png` and `rebuilt-logo-icon-state.txt` in the rebuilt ISO proof folder. The ISO artifact is `/Users/will/github/posthogos-live-iso/out/desktop/posthogos-desktop-linux-260513.iso`, and its `.sha256` check passed after the final rebuild.

Loop status: continue from `/Users/will/github/posthogos-live-iso/artifacts/visual-review/20260513-0837-logo-rebuilt-proof/rebuilt-logo-desktop.png` after the next compaction. Do not mark the goal complete until Will approves the screenshots or asks for a final handoff.

## Scope

- Use CachyOS Live ISO as the Arch-based distro base.
- Replace the live desktop and installer-adjacent branding with PostHogOS styling: OS identity, boot menus, KDE theme defaults, wallpaper, native welcome launcher, and desktop launchers.
- Apply PostHog website theming to the native Linux desktop. The literal website layout is out of scope. The OS should feel like the PostHog website through color, typography, icon style, menu bars, panels, buttons, borders, textures, and illustrations.
- Do not recreate the PostHog homepage navigation bar, `Dashboard` button, or full homepage content as desktop wallpaper or native chrome. Linux menu bars and panels should stay OS-shaped, just styled with the PostHog visual language.
- Use real visual assets referenced by the local `/Users/will/github/posthog.com` source where possible, especially the keyboard garden wallpaper image and texture. If the repo source points at Cloudinary assets, vendor those assets into this ISO tree rather than drawing approximations.
- Bake PostHog source into the image at `/opt/posthogos/code/posthog`.
- Bake development software into the ISO package graph:
  - Cursor
  - Claude Code CLI
  - Claude Desktop
  - Codex CLI
  - Codex Desktop Linux package
  - GitHub Desktop
  - Docker engine
  - Docker Desktop
  - Node, Bun, pnpm, Python, Go, Rust, uv, and common build tooling
- Produce proof from the built ISO running in a VM, with screenshots of the native desktop, launchers, PostHog code checkout, Cursor, Claude, Codex, GitHub Desktop, Docker Desktop, and Docker CLI.

## Current styling direction

- KDE should use a light PostHog palette: `#E1D7C2` keyboard-garden desktop base with source texture, `#fdfdf8` windows, `#bfc1b7` borders, `#eb9d2a` primary buttons, `#f54e00` strong accents, and IBM Plex Sans.
- The wallpaper should be a native desktop wallpaper: PostHog texture plus the real keyboard garden illustration, with plenty of empty space for windows and launchers.
- The wallpaper background should visually match the PostHog website keyboard-garden background: `#E1D7C2` plus the source `keyboard_garden_bg_light` texture from `/Users/will/github/posthog.com/src/components/Desktop/index.tsx` and `/Users/will/github/posthog.com/src/hooks/useTheme.tsx`. Do not swap in a plain grid, gray wash, or hand-drawn approximation.
- The KDE panel should be a fixed, full-width top OS bar. It should not float, have rounded screen-edge corners, or look like the default Plasma panel. Use the warmer PostHog bar colour `#e4e3d8`, a subtle `#bfc1b7` bottom border, dark text/icons, and enough height/padding that the clock/date does not feel cramped.
- The KDE panel, launcher, dialogs, window titlebars, native app launchers, and welcome flow should carry the PostHog theme. They should still look and behave like a Linux desktop.
- The previous screenshot failure mode was recreating the website's homepage/menu chrome in the wallpaper. Avoid that.

## Build path

Run this on an Arch or CachyOS build host:

```bash
./posthogos/build-local-repo.sh
sudo ./buildiso.sh -p desktop -v -w
```

The local repo step builds AUR and custom packages first, then patches `archiso/pacman.conf` so the ISO build resolves those packages during pacstrap.
