# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workspace Layout

This is the **jiji** development workspace. It is a git repo that tracks workspace-level docs and scripts. The actual source code for the jiji compositor (hard-fork of niri) and its tools lives in nested repos (not tracked by this repo).

Jiji is a hard fork of niri. The hard-fork strategy DD lives in the private overlay (`private/docs/jiji-fork.md`); see [Private overlay](#private-overlay) below.

### Nested repos (gitignored under `repos/`)

All repos are tracked by `repos.conf` and managed by the `workspace` script (`workspace status`, `workspace clone`, etc.). Run `./tools/workspace-install/install.sh && ./tools/cdr/install.sh` once to enable `workspace` and `cdr` from any cwd.

#### Compositor
- **`repos/jiji/`** — The jiji compositor (hard-fork of niri, [`jiji-wm/jiji`](https://github.com/jiji-wm/jiji)). Tracks `niri-wm/niri` upstream as a git remote for periodic rebases. Has its own `CLAUDE.md`. The source rename has landed: `Cargo.toml` is `[package] name = "jiji"`, the binary is `jiji`, the sub-crates are `jiji-ipc` / `jiji-config` / `jiji-visual-tests`, and the IPC env var is `$JIJI_SOCKET`. Still deferred: the `Niri` struct / `crate::niri` code-identifier surface.
- **`repos/upstream/niri/`** — Upstream niri compositor ([niri-wm/niri](https://github.com/niri-wm/niri)). Kept as a read-only mirror for rebase reference. Has its own `CLAUDE.md`.

#### CLI tools
- **`repos/jiji-activities/`** — The `jiji-activities` CLI binary (Rust, [`jiji-wm/jiji-activities`](https://github.com/jiji-wm/jiji-activities)). Has its own `CLAUDE.md` and DD at `repos/jiji-activities/docs/design.md`.
- **`repos/jiji-do/`** — Helix-style command launcher (Rust, [`jiji-wm/jiji-do`](https://github.com/jiji-wm/jiji-do)). Has its own `CLAUDE.md` and owning DD at `repos/jiji-do/docs/design.md`. Dependency contract: **no `niri-ipc` / `jiji-activities` Cargo dep** — all compositor/activities interaction is via `jiji msg` / `jiji-activities` subprocesses.
- **`repos/jiji-firefox-workspaces/`** — Native-messaging host restoring Firefox windows to their workspaces (Rust, [`jiji-wm/jiji-firefox-workspaces`](https://github.com/jiji-wm/jiji-firefox-workspaces)). Same subprocess dependency contract.
- **`repos/jiji-hamster-bridge/`** — Daemon pausing/resuming hamster time tracking from jiji activity/workspace focus (Rust, [`jiji-wm/jiji-hamster-bridge`](https://github.com/jiji-wm/jiji-hamster-bridge)). Has its own `CLAUDE.md`. Same dependency contract as jiji-do (compositor via `jiji msg` subprocess, `JIJI_MSG_BIN` override); hamster via `org.gnome.Hamster` D-Bus. **Deployment human-gated**: install binary, write real config, enable systemd user unit, chezmoi add, INSTALL-debian.md entry — runbook in the repo README.

#### Waybar
- **`repos/jiji-waybar/`** — Jiji's Waybar fork ([`jiji-wm/jiji-waybar`](https://github.com/jiji-wm/jiji-waybar)). Branch `main` adds jiji-specific activities modules; stays MIT (tracks upstream Waybar).
- **`repos/upstream/waybar/`** — Upstream Waybar ([Alexays/Waybar](https://github.com/Alexays/Waybar)). Read-only mirror for rebase reference.

#### Awesome list
- **`repos/reference/awesome-niri/`** — Curated awesome-list for niri ([niri-wm/awesome-niri](https://github.com/niri-wm/awesome-niri)). Community contribution to upstream niri — keeps the niri name.

### Private overlay

Internal design docs, specs, plans, and live development status are **not** in this public repo. They live in a private overlay repo cloned into the gitignored `private/` directory (same mechanism as `repos/`). Without it, `private/` is simply absent and everything degrades gracefully. It holds:

- `private/docs/jiji-fork.md` — hard-fork strategy DD.
- `private/docs/activities/` — compositor Activities feature design + exploratory analyses (the compositor loop's owning DD).
- `private/docs/launcher/` — launcher initiative.
- `private/docs/superpowers/` — specs + plans.
- `private/docs/status.md` — live per-loop development status (Resume cues), maintained by the scribe.

### Scripts

- `scripts/clone.sh` — Clone all nested repos (run once after cloning this workspace repo).
- `scripts/build.sh [target]` — Release build of any workspace project; `--targets` lists them (defaults to `upstream`). Targets: `upstream`, `jiji`, `jiji-activities`, `jiji-do`, `jiji-firefox-workspaces`, `jiji-hamster-bridge`. Target registry shared with install.sh lives in `scripts/project-targets.sh`.
- `scripts/install.sh [target]` — Compositor targets (`upstream`/`jiji`) install binary + session files to `/usr/local/`; tool targets `cargo install --offline` into `~/.cargo/bin`, plus — when the tool repo ships `systemd/<bin>.service` — the per-user unit into `~/.config/systemd/user/` with daemon-reload + try-restart (enable stays manual/one-time). Fish completes both scripts' first positional dynamically via `tools/workspace-install/fish/conf.d/jiji-build-scripts.fish`.
- `scripts/uninstall.sh` — Remove installed files (handles both `niri` and `jiji` names during the transition).

## Quick Reference

### Initial setup
```sh
./scripts/clone.sh      # clone nested repos
```

### Building & installing
```sh
./scripts/build.sh      # release build (upstream)
./scripts/build.sh jiji # release build (the fork)
./scripts/install.sh    # install to system
```

### Running tests (from the active fork)
```sh
cd repos/jiji           # or repos/upstream/niri
cargo test --all --exclude jiji-visual-tests
```

### Formatting & linting (from the active fork)
```sh
cd repos/jiji           # or repos/upstream/niri
cargo +nightly fmt --all
cargo clippy --all --all-targets
```

## Design Documents

### Compositor

The compositor's design docs (hard-fork strategy, the Activities feature design, and exploratory analyses) live in the **private overlay** under `private/docs/` — `jiji-fork.md`, `activities/design.md` (the compositor loop's owning DD, workspace-as-atom model), `activities/column-sharing.md`, `activities/persistence-forking.md`.

### CLI (sibling repos)

- **`repos/jiji-activities/docs/design.md`** — Implementer-grade DD for the `jiji-activities` CLI. Owned by the CLI loop; lifted from the compositor activities DD and expanded.
- **`repos/jiji-do/docs/design.md`** — Owning DD for the `jiji-do` launcher (skeleton + capability detection, design + phased implementation checklist).

## Active work

Live per-loop development status (Resume cues, phase/stage progress, test baselines) lives in the private overlay at `private/docs/status.md`. It's maintained by the loop scribe and is not part of the public skeleton.

## Sub-agent loops

All loops share one role-based agent set and one flat command set in `.claude/`, driven by the `<target>` registry in `loops.conf`. The implementer specializes by language; architect / fixer / scribe are language-agnostic. Full layout (agents, commands, autonomous `--autonomous` mode, orchestrator halt conditions, and log locations) is in [`docs/loops/architecture.md`](docs/loops/architecture.md); the day-to-day workflow guide is [`docs/loops/jiji-loop.md`](docs/loops/jiji-loop.md).

Three drivers: typed `/jiji:land-subphase <target>` (interactive, one sub-phase per `go`/`scribe`), `scripts/loop-subphase.sh <target> [N]` (detached autonomous), and `/jiji:loop <target> [N]` (in-session autonomous chain — spawns the detached script one iteration at a time, summaries inline, halts return to the session). The retired `/jiji:flow` Workflow-tool attempt and why a conversational loop replaced it are written up in [`docs/loops/workflow-tool-findings.md`](docs/loops/workflow-tool-findings.md).

**`SendMessage` architect-resume (layered).** When run with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (which enables `SendMessage` — resume a completed background agent *with full context*), `/jiji:land-subphase` resumes the same named architect instead of re-dispatching a fresh one, preserving its full reasoning. Availability is governed by **process ownership, not gate-mode**: because the flag is set in `.claude/settings.json` `env` it reaches *every* invocation including headless `claude -p` children, so you can resume any architect *you* spawned. The two resume occasions split by mode: the interactive Step 2 revision/answer is human feedback (interactive only), while the **automatic Step 5 escalation (fixer → architect) is resumable in all modes** — interactive, autonomous main-session, and the autonomous `claude -p` child driving its own sub-phase. The only unreachable case is the `/jiji:loop` *outer* session reaching a child's architect, which never arises (resume happens inside the child). It is layered on, never load-bearing: the flag is experimental and double-gated, so re-dispatch is always the fallback. Full rule in [`.claude/commands/jiji/land-subphase.md`](.claude/commands/jiji/land-subphase.md) (*Architect resume*).

Fork-specific coding conventions live in `repos/jiji/CLAUDE.md`. CLI conventions live in the jiji-activities repo's `CLAUDE.md`.

When starting a new compositor-side feature, create its design doc under `private/docs/` and update `private/docs/status.md`. New CLI features go in the relevant tool repo and update its DD.

## Compositor Architecture (key concepts)

Crate structure, the post-Phase-0b-2 `Layout`/`Monitor`/`Workspace` hierarchy, key ID types, the `$JIJI_SOCKET` IPC protocol, workspace-switching internals, and window rules are documented in [`docs/compositor-architecture.md`](docs/compositor-architecture.md).

## Important

- Each subdirectory is its own git repo — always `cd` into the correct one before running git commands. Read the subdirectory's `CLAUDE.md` before working in it.
- The parent directory (`de/`) contains many niri ecosystem tools organized by category. See `../CLAUDE.md` for a full inventory.
- The curated list with upstream links lives in `repos/reference/awesome-niri/README.md`.

## After any config or tooling changes

When you modify desktop config files (waybar, niri/jiji, swaync, etc.) or install new packages/tools:

1. **Update `INSTALL-debian.md`** — Add any new packages, build deps, or setup steps so the install guide stays complete and reproducible on a fresh machine.
2. **Update `keybindings.md`** — If keybindings changed, keep the reference doc in sync.
3. **Update chezmoi** — Run `chezmoi add <changed files>` to sync config files into the chezmoi source repo (`~/.local/share/chezmoi/`). Then commit the changes there. This ensures configs are deployable to other machines via `chezmoi apply`.
4. **System-level configs (keyd, udev)** — These can't be managed by `chezmoi add`. They're deployed by the chezmoi install script (`run_onchange_install-packages.sh.tmpl`). Update the embedded config in that script and the chezmoi README when changing `/etc/keyd/default.conf` or similar files.

Both repos (this one and chezmoi at `~/.local/share/chezmoi/`) need separate commits.

Both steps are required before committing — the goal is that the full desktop setup is reproducible from the install doc + chezmoi repo alone.

## After CLI surface changes (jiji compositor, jiji-activities)

When you add, remove, or rename a subcommand or flag in **the jiji compositor** (`repos/jiji/src/cli.rs`) or **jiji-activities** (`repos/jiji-activities/src/cli.rs`):

1. **Reinstall the binary via `./scripts/install.sh <target>`** (e.g. `jiji`, `jiji-activities`, `jiji-do`). The installed binary is what emits its own `completions <shell>` output, so a stale install means a stale completion file. Since 2026-06-06 the install script also regenerates the local fish completion (`~/.config/fish/completions/<bin>.fish`) from the freshly installed binary, so the local machine never needs a separate completion step. (A bare `cargo install --path . --offline` still works but skips the completion regen — prefer the script.)
2. **Bump `# hash:` in chezmoi's `run_onchange_install-packages.sh.tmpl`.** This forces the `run_onchange_` script to re-fire on the next `chezmoi apply`, regenerating the fish completions (`jiji.fish`, `jiji-activities.fish`, `jiji-do.fish`) against the installed binaries. With step 1 handling the local machine, this matters for **other/fresh machines** — and chezmoi remains the owner of the stale pre-rename file sweeps (`niri.fish`, `niri-activities.fish`).
3. **For jiji-activities only:** if the change adds, renames, or removes a subcommand whose first positional is an *existing* activity name, also update `FISH_SINGLE_ARG_VERBS` in `repos/jiji-activities/src/completions.rs`. **Read the `Cmd` variant shape before deciding** — a unit variant (`AssignWorkspace,`) means no positional, so it must NOT go in the dynamic set even if its description talks about "one or more activities" (those are picker rows, not CLI args). New-name verbs (`create`-like) also stay out. `clap_complete`'s base output auto-tracks the clap-derive surface so the static parts of the completion never go stale; only the dynamic activity-name lines need manual sync. See `repos/jiji-activities/CLAUDE.md` for the full discipline.

The compositor's completion is fully `clap_complete`-derived (no manual augmentation), so step 3 only applies to jiji-activities.
