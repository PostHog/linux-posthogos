# PostHogOS style workflow

This folder is the approval gate for the native PostHogOS styling pass.

## Stages

1. Build and approve the PostHog website style source doc.
2. Build and approve the CachyOS/KDE GUI manipulation context doc.
3. Apply the approved style system to the distro and verify it from a real VM boot.

## Docs

- `posthog-website-style-source.md`: source-backed PostHog visual system extracted from `/Users/will/github/posthog.com`.
- `distro-gui-manipulation-context.md`: source map for the local ISO, KDE, Plasma, wallpaper, launcher, and runtime APIs where native style changes land.
- `visual-match-review-loop.md`: screenshot-driven review loop for comparing the live PostHog homepage against the native PostHogOS VM.

## Hard rules

- Style native Linux GUI surfaces. Do not recreate PostHog.com as a browser page or wallpaper screenshot.
- Use local PostHog website source assets or source-referenced assets.
- Keep implementation changes tied to approved docs.
- Keep iterating with reference screenshots, VM screenshots, and written self-review until the visible OS theme match is good enough for Will to approve.
