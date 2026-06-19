# Sub-agent loops — structure and autonomous mode

The day-to-day workflow guide is `docs/loops/jiji-loop.md`. This file documents the agent/command layout and the orchestrator-driven autonomous mode.

## Structure

All loops share **one** role-based agent set and **one** flat command set in this workspace's `.claude/`. The implementer is chosen by **language** (resolved from `loops.conf`); architect / fixer / scribe are language-agnostic.

```
.claude/
  agents/
    jiji-architect.md        (language-agnostic; resolves target via loops.conf, reads target repo CLAUDE.md)
    jiji-rust-implementer.md (Rust implementer; one per language — add jiji-<lang>-implementer for a new language)
    jiji-js-implementer.md   (JavaScript/WebExtension implementer; serves the ff-restore-ext extension loop)
    jiji-fixer.md            (language-agnostic)
    jiji-scribe.md           (language-agnostic; resolves dd_path + dd_commit_repo via loops.conf)
    jiji-architect-pass.md   (cross-phase gap analysis, invoked by /jiji:architect-pass)
    jiji-refactor-pass.md    (cross-phase cognitive-friction analysis, invoked by /jiji:refactor-pass)
  commands/
    jiji/
      land-subphase.md   → /jiji:land-subphase <target> [--autonomous] [sub-phase]
      loop.md            → /jiji:loop <target> [max_iter]
      next-subphase.md   → /jiji:next-subphase <target> [sub-phase]
      implement.md       → /jiji:implement <target>
      apply-review.md    → /jiji:apply-review <target>
      scribe-review.md   → /jiji:scribe-review <target> [hashes]
      architect-pass.md  → /jiji:architect-pass [compositor|cli]
      refactor-pass.md   → /jiji:refactor-pass [compositor|cli|both]
      initiative.md      → /jiji:initiative [status|note|done]
```

The flat commands take **`<target>` as their first argument** and resolve it against **`loops.conf`** (the loop-target registry: `name|language|code_repo|dd_path|dd_commit_repo`). Registered targets today: `compositor`, `cli`, `jiji-do`, `ff-restore` (Rust host), `ff-restore-ext` (JS — the Firefox extension half), and `ff-restore-comp` (Rust — compositor-side boxes of the ff-restore DD, code in `repos/jiji`). Adding a loop is one `loops.conf` row (plus, only for a genuinely new language, one `jiji-<language>-implementer` — `js` added 2026-06-03 for the extension fork). **`ff-restore` + `ff-restore-ext` + `ff-restore-comp` share one DD** (`repos/jiji-firefox-workspaces/docs/design.md`) split by component + language; always name the box explicitly when landing against it.

**Scope discipline.** One agent set serves every target. **Per-codebase discipline lives in each target repo's `CLAUDE.md`**, not in the agents — the compositor's invariant-check + test-bucket arithmetic in `repos/jiji/CLAUDE.md`, the CLI's `assert_cmd`/exit-code rigor in `repos/jiji-activities/CLAUDE.md`. The architect, fixer, and scribe read the target repo's `CLAUDE.md` for that context; only the **implementer specializes, and only by language** (`jiji-rust-implementer` today). This keeps the agents stable as targets are added: a new Rust tool costs zero new agents, a non-Rust tool costs one implementer, a non-CLI Rust tool costs only its own repo `CLAUDE.md` discipline.

## Autonomous mode (orchestrator-driven)

The loop supports an `--autonomous` flag that runs the full sub-phase end-to-end without the Step 2 / Step 6 human gates. Designed for `claude -p` invocation from the orchestrator script, **not for typing into an interactive Claude session** — interactive runs should keep using the bare command and respond to gates with `go` / `scribe`.

| Mode | Invocation | Iteration | Gates 2 + 6 |
|---|---|---|---|
| Interactive | `/jiji:land-subphase <target>` (typed) | One sub-phase per `go`/`scribe` exchange | Stop, await human |
| Autonomous (detached) | `scripts/loop-subphase.sh <target> [N]` | N fresh `claude -p` sessions, back-to-back | Pass automatically; halt on conditions below |
| Autonomous (in-session) | `/jiji:loop <target> [N]` | N detached iterations spawned one at a time from this session; each summary prints inline, halts return here | Pass automatically; halt on conditions below |

`<target>` is a name registered in `loops.conf`; both drivers validate it against the registry and refuse anything else.

`/jiji:loop` is the in-session L3 driver: it spawns `scripts/loop-subphase.sh <target> 1` one iteration at a time (re-entering on the background-completion notification, with a 30-min `ScheduleWakeup` fallback), summarizes each landed sub-phase inline via a haiku agent, and returns to the live session on any halt for an interactive decision. The detached script stays the single source of truth for *batch* logic; `/jiji:loop` only owns the iteration chain and a per-iter conversation surface. Chain state persists in a marker at `~/.cache/jiji-loop/<target>-chain<ts>.chain`, so a re-entered session can resume. (A failed `Workflow`-tool variant, `/jiji:flow`, was retired — see `docs/loops/workflow-tool-findings.md` for why the conversational driver won.)

Halt conditions (the orchestrator stops cleanly with a `claude --resume <id>` hint and a desktop notification):

- `architect-open-questions` — DD defect or ambiguity surfaced at Step 2.
- `fixer-cap` — fixer hit round 3 without converging.
- `phase-complete` — DD has no remaining `[ ]` boxes after the scribe's update.
- `test-delta` — unexplained test count change vs. baseline.
- `decision-needed` — any agent escalates an explicit human-judgment ask.
- `ratification` — a human-only design-ratification box reached.
- `LOOP_ERROR` — irrecoverable issue (broken main, dirty tree, etc.).

Why fresh sessions: the orchestrator deliberately runs each iteration in its own `claude -p` process so the Anthropic prompt cache resets and long-context retrieval stays at peak quality. The DD plus git history is the persistent state across iterations, not the conversation. Default `N=4` keeps total context comfortably below the auto-compaction cliff even for non-Mechanical sub-phases.

**Where the logs are.** Three layers, each useful for a different purpose:

| Log | Path | Live? | Use for |
|---|---|---|---|
| Orchestrator run log | `~/.cache/jiji-loop/<loop>-<timestamp>.log` | yes (`tee`'d to terminal) | iteration banners, signal results, halt reasons |
| Per-iteration JSON capture | `~/.cache/jiji-loop/<loop>-iter<N>-<HHMMSS>.json` | no — flushed at iter end | source of the parsed `LOOP_*` signal; full agent output for post-mortem |
| **Agent live transcript** | `~/.claude/projects/<flattened-workspace-path>/<session-id>.jsonl` | **yes — appended in real time** | watching the agent think while it works |

(The `~/.cache/jiji-loop/` cache dir name follows the workspace rename. Old logs under `~/.cache/niri-loop/` survive as a historical record.)

The orchestrator prints both a raw `tail -f` command and a `scripts/loop-tail.sh <session-id>` invocation at the start of each iteration. Run either command in a separate terminal alongside the orchestrator.
