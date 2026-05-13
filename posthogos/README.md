# PostHogOS ISO layer

This directory contains the PostHogOS-specific layer on top of CachyOS Live ISO.

The important bit: the apps are baked into the ISO package graph. Post-boot live VM package installs are out of scope.

## Build

Use an Arch or CachyOS builder with `base-devel`, `archiso`, `git`, and `repo-add` available.

```bash
./posthogos/build-local-repo.sh
sudo ./buildiso.sh -p desktop -v -w
```

From macOS with Docker Desktop:

```bash
./posthogos/docker-build-iso.sh
```

Set `POSTHOGOS_REBUILD_REPO=1` when you want to rebuild the local pacman repo instead of reusing `posthogos/repo/x86_64/posthogos-local.db.tar.gz`.

The local repo script builds:

- AUR packages: `cursor-bin`, `docker-desktop`, `github-desktop-bin`, `claude-desktop-bin`
- Codex Desktop Linux package from `ilysenko/codex-desktop-linux`
- Custom packages: `posthogos-ai-clis`, `posthogos-branding`, `posthogos-posthog-code`

Then it creates `posthogos/repo/x86_64/posthogos-local.db.tar.gz` and inserts a `[posthogos-local]` repo block into `archiso/pacman.conf`.

## VM proof checklist

Boot the generated ISO in QEMU or VMware and capture:

- Boot menu showing PostHogOS labels.
- KDE desktop with PostHogOS wallpaper and dark/orange PostHog styling.
- Native PostHogOS welcome launcher.
- `/home/liveuser/code/posthog` opened in Dolphin or Konsole.
- Cursor opened against the PostHog checkout.
- Claude Code and Codex CLI launched from the PostHog checkout.
- Claude Desktop.
- Codex Desktop.
- GitHub Desktop.
- Docker Desktop and `docker version`.

## Known packaging caveat

`github-desktop-bin` is currently marked out-of-date in AUR. It is still included because it is the available Arch package for GitHub Desktop, but it should be reviewed before showing this as more than a hackathon artifact.

Codex Desktop is built from the community `ilysenko/codex-desktop-linux` project. The official Codex CLI is baked separately through `posthogos-ai-clis`.
