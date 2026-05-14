# PosthogOS Roadmap: The Agentic Development OS for 2026

## Positioning

> **An OS designed for the assumption that you're driving 10 agents at
> once.** Every default — shell, terminal multiplexer, container runtime,
> sandbox primitives, secret broker, filesystem layout — exists to make
> agent supervision, agent isolation, and agent measurement frictionless.

This is the lens for every "should we add X?" answer. If a default
doesn't earn its place in an agent-heavy workflow, drop it.

## What's already covered (don't reinvent)

**PostHog Code** (bundled as an AppImage at `/opt/posthog-code/`) is the
agent orchestrator: dispatching to Claude/Codex/etc., supervising runs,
diffing changes, auto-instrumenting to PostHog for observability. The OS
does NOT need its own `posthogos-agent` CLI or competing supervision
layer — PostHog Code IS that layer. The OS's job is to make PostHog Code
the optimal substrate to run on.

## What PosthogOS needs to provide

Four tiers, ordered by the degree to which each enables PostHog Code.

### Tier 1 — substrate PostHog Code depends on

| Capability | Default ship | Why |
|---|---|---|
| AI CLIs callable by PostHog Code | `claude-code`, `openai-codex`, `aider`, `gemini-cli` preinstalled (PKGBUILDs or AUR) | PostHog Code can shell out to these; users get them for direct CLI use too |
| Local model inference | `ollama` + auto-pull of a coding model at first boot (Qwen Coder or similar) | Privacy, offline, free baseline. PostHog Code can target the local endpoint when no API key is set |
| MCP server farm | Filesystem, GitHub, Postgres, Slack, Linear, Playwright, web-fetch, RAG-over-docs MCPs preinstalled; one `~/.config/posthogos/mcp.json` wires them in | MCP is the universal protocol; ship the servers, let PostHog Code consume them |
| Container runtime | `docker` (already bundled) + `podman` + `distrobox` + `lazydocker` | Agents frequently spin up containers for isolation and reproducibility |
| Language toolchain manager | `mise` (or `asdf`) preconfigured, plus baseline Python/Node/Rust/Go/Bun/Deno | Agents need to invoke arbitrary toolchains; one source of truth beats six per-language installers |

### Tier 2 — agent-safe development environment

Without these primitives, users don't trust agents to do anything
irreversible.

| Capability | Default ship | Why |
|---|---|---|
| Btrfs root + snapper | Calamares already supports btrfs; configure snapper for hourly snapshots + on-demand "pre-experiment" snapshots | One command rolls back any agent's filesystem damage |
| Sandboxing primitives | `bubblewrap`, `firejail`, `nsjail` preinstalled with sensible policy presets | Run agents with read-only `/`, no network, scoped filesystem access |
| Secret broker | `pass` + `age` + `sops` + 1Password CLI + Bitwarden CLI | Agents request a secret, get prompted for approval, never see the raw value |
| Network audit | `mitmproxy` preinstalled, optional flag to route agent traffic through it | Records every HTTP call an agent makes for after-the-fact review |
| Disposable dev envs | `distrobox` images preconfigured for "throw away after this experiment" | Heavier than bubblewrap, lighter than a VM |

### Tier 3 — modern developer baseline

Bring the shell experience up to 2026 standards. Agents read shell
output too — better tools = better agent comprehension.

| Category | What we ship |
|---|---|
| Shell | `zsh` (CachyOS default) with `starship` prompt + `atuin` + `zoxide` preconfigured |
| File/text tooling | `bat`, `eza`, `ripgrep`, `fd`, `fzf`, `delta`, `jq`, `yq` |
| Git | `gh`, `lazygit`, `glab`, `tig`, `delta` |
| System | `btop`, `dust`, `tokei`, `hyperfine`, `procs` |
| Task runner | `just` as the de-facto `Makefile` replacement |
| HTTP | `xh` (httpie alternative) + `curl` |
| Terminal multiplexer | `zellij` (default) with PostHog-branded layouts |
| Cloud CLIs | `aws`, `gcloud`, `kubectl`, `helm`, `terraform`, `k9s`, `flyctl`, `tailscale` |
| Database clients | `psql`, `mysql-shell`, `redis-cli`, `mongosh`, `sqlite3`, `duckdb` |
| Browser automation | `playwright` (chromium pre-pulled) for headless scraping/testing |

### Tier 4 — identity and onboarding

What makes this *the PostHog OS*, not generic Linux with stickers.

| Touch point | What we do |
|---|---|
| Welcome window | Replace the current 4-tile welcome with: "(1) Launch PostHog Code → (2) sign into your preferred AI CLI → (3) connect your MCP services". The OS welcome's job is to hand off to PostHog Code, not duplicate it |
| First-boot onboarding | A guided flow that auto-runs `ollama pull <model>`, prompts for API key entry (stored via `pass`), and walks the user through their first agent invocation in PostHog Code |
| Branded `.posthog/` convention | Like `.cursor/rules` or `.claude/`, a `.posthog/` directory in any repo gets discovered by PostHog Code AND surfaced in the welcome window AND used to seed agent contexts |
| Default shell prompt | `starship` config preinstalled with PostHog brand colors |
| Plymouth + GRUB splash | Already shipped but minimal; polish to match welcome aesthetic |
| Wallpaper | Default to one of the hoglife wallpapers; eventually add the maze/labyrinth Product OS pattern matching posthog.com |

## Architectural shifts to evaluate

These are larger commitments worth deliberate decisions before
expanding the feature surface.

### Atomic / immutable base (deferred decision)

Following the Bazzite/Aurora/Bluefin pattern, build PosthogOS as an
`rpm-ostree` / `bootc` image rather than a mutable Arch install.

**Pros for an agentic OS:**
- Agents physically cannot permanently break the system (every change
  is a transaction, every update is rollback-able at the boot layer)
- Reproducible — every PosthogOS install is byte-identical at the
  base layer
- Atomic updates with zero half-installed states

**Cons:**
- Bigger lift to switch from our current pacstrap-based build
- Less Arch-native; loses the "you can `pacman -S whatever`" flexibility
- Bootc tooling is less mature than the existing arch/calamares flow

**Decision needed:** ship-and-iterate on the current pacstrap approach
through 2026 Q2; revisit immutability when the user complaint surface
makes it obvious it'd help.

### Btrfs root by default

Calamares already supports btrfs install; we just need to make it the
default in our settings + add `snapper` config out of the box.

**Decision:** YES, do this. It's a prerequisite for the Tier 2 snapshot
story, low risk, well-understood.

### Distrobox/Flatpak as primary GUI app channel

Reserve pacman for system packages and CLI tools; use Flatpak for
sandboxed GUI apps (Slack, Spotify, etc.) and distrobox for "I need a
specific Ubuntu toolchain for this one project."

**Decision:** Add Flatpak as a secondary channel (`flatpak` preinstalled,
Flathub configured); don't force-migrate existing apps.

## What we're explicitly NOT doing

- **`posthogos-agent` CLI** — PostHog Code IS the agent orchestrator,
  no point in a competing wrapper.
- **Multi-agent orchestration framework** (langgraph/crewai/etc.) — also
  PostHog Code's domain or the user's own tooling, not the OS's.
- **Model training/serving** — Ollama provides inference, that's where
  the OS's involvement stops.
- **Custom AI model from PostHog** — out of scope; we consume what's
  available.
- **Heavy KDE accessory bundle** — gimp, kate, kcalc, accessibility
  apps we don't use. Drop them to free disk + simplify the system.

## Near-term work sequence

Ordered by leverage-per-day.

| Phase | Work | Time | Why it goes first |
|---|---|---|---|
| **A** | Verify Calamares install actually completes end-to-end on a real qcow2. Boot the installed system, confirm firstrun fires, PostHog Code launches | 1 day | Highest unverified risk in the whole project today |
| **B** | Bundle the AI CLI stack (Claude Code, Codex, Aider) as PKGBUILDs in a small `posthogos` pacman repo (or AUR helpers in the live ISO) | 2-3 days | Direct enabler for PostHog Code + standalone CLI use |
| **C** | Switch Calamares default to btrfs + ship snapper config in `/etc/skel/.config/snapper/` | 1 day | Prerequisite for snapshot-on-experiment. Low risk, immediate user benefit |
| **D** | MCP server farm preinstalled with `~/.config/posthogos/mcp.json` defaults | 2 days | The multiplier — PostHog Code becomes 10× more useful with tools |
| **E** | Ollama preinstalled with auto-pull of a coding model on first boot (gated by disk space) | 1 day | Offline / private fallback for cost-sensitive workloads |
| **F** | Modern shell tooling pass (Tier 3 table above) added to package list, plus a curated `zellij` layout in `/etc/skel/.config/zellij/` | 1 day | Quality-of-life across the board; agents see better output |
| **G** | Curate package list: drop ~50 packages of unused KDE accessories, replace some defaults with modern alternatives | 1 day | Smaller ISO, simpler system |
| **H** | Welcome window redesign: PostHog Code handoff flow + MCP setup + AI CLI sign-in | 2-3 days | Identity moment; first impression for new users |
| **I** | Plymouth + boot splash polish | 0.5 day | Aesthetic completion of the boot-to-login sequence |
| **J** | Lift Will's OCR Calamares install tests into CI | 2-3 days | Once stabilized, this protects every PR from install-path regressions |

**Total**: ~3 weeks of focused work for items A-J, in priority order.
First week (A-C) gets the install path validated + the agentic
substrate cohesive. Second week (D-F) makes PostHog Code's runtime
environment optimal. Third week (G-J) is polish + protection.

## Decisions parked for later

Things worth a deliberate call once we have more usage data.

- **Atomic base** (rpm-ostree / bootc migration)
- **Custom PostHog dev analytics dashboards** ship with the OS or live
  on cloud only
- **Hardware target expansion** — currently x86_64 only; aarch64 native
  build for Apple Silicon / ARM cloud instances
- **Encrypted home by default** (Calamares supports it; we don't
  currently default it)
- **PostHog org SSO integration** for AI CLI key provisioning
