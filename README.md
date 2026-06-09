# jiji workspace

Development workspace for **jiji**, a hard-fork of the [niri](https://github.com/niri-wm/niri) Wayland compositor. Contains workspace-level docs, build/install scripts, and references to nested source repos.

Jiji is a hard fork (binary, env vars, IPC crate names, resource files all renamed to `jiji-*`) that tracks niri upstream as a git remote for periodic rebases. The hard-fork strategy and rename timeline are documented in the private overlay (`private/docs/jiji-fork.md`; see [Private overlay](#private-overlay)).

## Setup

```sh
# Clone all nested repos (registry: repos.conf)
./scripts/clone.sh

# Build and install
./scripts/build.sh                    # upstream niri
./scripts/build.sh jiji               # the jiji fork
./scripts/install.sh jiji             # install jiji (system-wide, sudo)
./scripts/install.sh jiji-activities  # CLI tools go to ~/.cargo/bin
./scripts/build.sh --targets          # list all targets
```

## Structure

Nested repos live under `repos/` (gitignored; registry in `repos.conf`, managed by the `workspace` script):

| Path | Description |
|---|---|
| `repos/jiji/` | The jiji compositor (hard-fork of niri) |
| `repos/jiji-activities/` | `jiji-activities` CLI — KDE-style activities for jiji |
| `repos/jiji-do/` | `jiji-do` — Helix-style command launcher |
| `repos/jiji-firefox-workspaces/` | Per-workspace Firefox window restore (native host + WebExtension) |
| `repos/jiji-hamster-bridge/` | Activity-driven [hamster](https://projecthamster.org/) time-tracking bridge |
| `repos/jiji-waybar/` | Waybar fork with jiji activities modules |
| `repos/upstream/niri/` | Read-only mirror of [niri-wm/niri](https://github.com/niri-wm/niri) for rebase reference |
| `repos/upstream/waybar/` | Read-only mirror of [Alexays/Waybar](https://github.com/Alexays/Waybar) |
| `repos/reference/awesome-niri/` | Curated [awesome-niri](https://github.com/niri-wm/awesome-niri) list (community contribution to upstream) |

Workspace-level:

| Path | Description |
|---|---|
| `scripts/` | Build, install, clone helpers + `loop-subphase.sh` (autonomous orchestrator) and `loop-tail.sh` (transcript tail) |
| `tools/` | `workspace`/`cdr` installers, loop observability, `strip-review-needed` |
| `docs/` | Compositor architecture reference + the loop workflow guide under `docs/loops/` (design DDs live in the private overlay) |
| `.claude/` | Claude Code subagents + slash commands for the DD-driven phase loops |
| `INSTALL-debian.md` | Full Debian install guide |
| `keybindings.md` | Keybinding reference |

### Private overlay

Internal design docs, specs, plans, and live development status are **not** in this public repo. They live in a private repo cloned into the gitignored `private/` directory by `scripts/clone.sh` (skipped automatically without access). It holds the hard-fork strategy DD (`private/docs/jiji-fork.md`), the compositor Activities feature design (`private/docs/activities/`), the launcher initiative, specs/plans, and the live per-loop status (`private/docs/status.md`). Public contributors get an empty `private/` and everything degrades gracefully.

## Docs

- **[INSTALL-debian.md](INSTALL-debian.md)** — Reproducible Debian setup guide
- **[keybindings.md](keybindings.md)** — Keybinding reference
- **[CLAUDE.md](CLAUDE.md)** — Claude Code workspace instructions
- **[docs/compositor-architecture.md](docs/compositor-architecture.md)** — Compositor layout/IPC architecture reference
- **[docs/loops/jiji-loop.md](docs/loops/jiji-loop.md)** — Developer's guide to the unified DD-driven phase loop (all targets in `loops.conf`)
- Design DDs, specs, and live status live in the **private overlay** (`private/`, see above)

## Autonomous sub-phase orchestration

The phase loops have an autonomous mode — `scripts/loop-subphase.sh <target> [N]` (targets from `loops.conf`) — that runs `N` sub-phases back-to-back via `claude -p`, each in a fresh session so context stays at peak quality. The orchestrator halts cleanly on architect open-questions, fixer non-convergence, phase completion, or any other human-decision condition; resume with `claude --resume <session-id>` (printed on halt). Default `N=4`. Logs at `~/.cache/jiji-loop/`. See **[CLAUDE.md § Autonomous mode](CLAUDE.md)** for halt conditions and rationale.

To follow the agent live while a sub-phase runs, use the companion **`scripts/loop-tail.sh`** — color-coded, one-line-per-event filter over the session JSONL transcript. Without args it tails the newest session; pass `-l` to list sessions or `-n N` to backfill history. The orchestrator banner already echoes the exact invocation per iteration.

Interactive single-step usage is unchanged: `/jiji:land-subphase <target>` inside a normal Claude Code session, with human gates at Steps 2 and 6.
