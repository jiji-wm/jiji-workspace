---
description: jiji loop — architect plans, human confirms, implementer codes, review runs, fixer cleans up, scribe documents. First arg selects the target from the loop registry.
argument-hint: <target> [--autonomous] [sub-phase name]
---

Full sub-phase landing loop for any registered jiji loop target. One agent set serves every target; the **language** (resolved from the registry) chooses which implementer runs.

## Step 0 — Resolve the target

Parse `$ARGUMENTS`: the **first token is the target** (e.g. `compositor`, `cli`). Resolve it from the workspace root:

```bash
scripts/loops-registry.sh <target> | awk -F'|' '{print "lang="$2" code="$3" dd="$4" ddrepo="$5}'
```

The resolver merges the public `loops.conf` with the specs overlay (`specs/<owner>/loops.conf`) — never parse either file directly. If it exits non-zero, **stop**: exit 1 means unknown (it prints the valid targets), exit 3 means the name is defined in both halves and one must be deleted. Otherwise bind `language` (field 2), `code_repo` (field 3) for this run. Strip the target token from `$ARGUMENTS`; the remainder (after also stripping a leading `--autonomous`) is the sub-phase name passed to the architect.

## Invocation modes

Selected by the post-target remainder of `$ARGUMENTS`:

- **Interactive** (default): human gates at Step 2 (after architect spec) and Step 6 (after fixer). Human types `go` / `scribe` to proceed.
- **Autonomous** (when the remainder starts with `--autonomous`, optionally followed by a sub-phase name): no human gates. Steps 2 and 6 pass automatically *unless* a halt condition fires. End the final message with a single `LOOP_*` signal line for the orchestrator. Designed for `claude -p` invocation from `scripts/loop-subphase.sh <target>`.

The mode only affects Steps 2, 6, and 8 — Steps 1, 3, 4, 5, 5b, 7 are identical. **Do not call `ScheduleWakeup`** in autonomous mode; the orchestrator owns iteration cadence.

### Architect resume (all modes, layered on `SendMessage`)

When `SendMessage` is available it resumes a completed/stopped background agent **with its full context retained** — so you can *resume the same architect* across a gate or an escalation instead of cold-dispatching a fresh one, preserving its full reasoning (the DD read, the hazard analysis), not just its distilled spec. This saves the re-derivation tokens and wall-clock of a fresh architect re-reading the DD and code, and is the reason to reach for it.

**When it is available — process ownership, not gate-mode.** `SendMessage` is enabled by `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Because this workspace sets that flag in `.claude/settings.json` `env` (not as a transient shell var), it propagates to **every** Claude Code invocation in the repo — interactive *and* headless `claude -p` children. So the precondition is **not** the gate-mode (interactive vs. `--autonomous`) but whether *you* — the currently-running driver process — spawned the agent you want to resume. That holds in all three run shapes:

- interactive `/jiji:land-subphase` in the main session — you spawned the architect; resume it;
- autonomous `/jiji:land-subphase --autonomous` in the main session — same; `--autonomous` only suppresses the human gates, it does **not** move the architect into another process;
- autonomous inside a `claude -p` loop child (spawned by `/jiji:loop` → `scripts/loop-subphase.sh`) — that child **is** the driver for its sub-phase and spawned its own architect, so it can resume it too.

The *only* unreachable case is the `/jiji:loop` **outer** session trying to reach a child's architect — and that never arises, because every architect-resume happens **within** the same process that ran the earlier architect step.

**Always consider resume vs. fresh dispatch** at each re-dispatch point. Prefer **resume** when the next step *continues* the same architect's work — a revision, an answer to its Open questions, or an escalated finding on the unit it just specced — because it keeps the full reasoning in context and is cheaper. Prefer a **fresh dispatch** when the work is genuinely new or unrelated (a different box/sub-phase), when the prior architect's context is stale or would mislead, or when `SendMessage` is unavailable. It is **layered on, never load-bearing**: the flag is experimental and double-gated (env var **plus** a server-side flag), so if `SendMessage` is absent or a resume call fails, fall back to a fresh `jiji-architect` dispatch — the unchanged default. **To keep the option open you must give the architect a stable, addressable `name` at dispatch (e.g. `architect-<target>`) and keep its `agentId` from the spawn result — in every mode, not just interactive.** The automatic Step 5 escalation (fixer → architect) is therefore resumable in autonomous runs too; the interactive Step 2 revision/answer path is the only one inherently gated to interactive mode (it is human feedback).

## Step 1 — Architect

Invoke `jiji-architect` with input `target=<target> sub-phase=<remainder>` (blank remainder = next unchecked `[ ]` box in the current phase, then scan ahead and combine consecutive boxes into one landing unit per the grouping criteria). The architect resolves the target's DD and `<code_repo>/CLAUDE.md` itself and produces a spec per its output format, carrying `## Language` and `## Target repo` routing metadata.

**All modes:** dispatch the architect with a stable `name` (e.g. `architect-<target>`) and retain its `agentId` from the spawn result, so Step 2 (interactive revision) and Step 5 (escalation, any mode) can `SendMessage`-resume it with full context when available (see *Architect resume* above). If `SendMessage` is absent this name is simply unused.

**Human-only ratification special-case:** if the next unchecked box is a human-only design-ratification box, the architect will STOP without producing a spec — those boxes are human-only DD decisions. Resolve them by editing the target's DD directly (flip `[ ]` → `[x]` per ratification, optionally with an amendment note), commit, then re-run `/jiji:next-subphase <target>` or `/jiji:land-subphase <target>`.

## Step 2 — Spec gate

**Interactive mode:** stop and wait for human review of the spec. Human says `go` to proceed, or asks the architect to revise.

On a revision request (or when the human answers the architect's `## Open questions`): if `SendMessage` is available, **`SendMessage{to: "architect-<target>" (or the retained agentId), message: <the human's answer / revision request>}`** to resume the *same* architect — it still holds its full reasoning, so it revises in context rather than re-deriving from a distilled prompt. Wait for the revised spec, then re-gate. If `SendMessage` is absent, fall back to re-dispatching `jiji-architect` with the answer/revision folded into its input (the unchanged default).

**Autonomous mode:** pass automatically — but inspect the architect's output first:

- If the architect's **`## Open questions`** section is non-empty, halt: emit `LOOP_HALT:architect-open-questions:<one-line summary>` as the final message and end. Do not invoke the implementer. (Open questions are reserved for architectural questions with no clear technical winner — UX policy, cross-loop coordination, backwards-compatibility — that genuinely need human judgment. Editorial and architecturally-resolvable DD issues are landed by the architect itself before producing the spec; they show up in `## DD updates landed`, not here.)
- If the architect stopped without producing a spec because the next box is a **human-only ratification box**, halt: emit `LOOP_HALT:ratification:<box title>` and end. Those boxes are human-only DD decisions.
- If the architect's **`## DD updates landed`** section is non-empty, this is informational — the architect has already committed DD edits to resolve editorial or architecturally-resolvable questions. Continue.
- If the architect's **`## DD updates proposed`** section is non-empty, this is non-blocking — the scribe folds the edits in at end of loop. Continue.

## Step 3 — Implementer

**Model selection:** read the spec's `## Complexity` section. If its first non-blank token is `Deep`, invoke the implementer with `model: "opus"` (Opus 4.7, 1M context). Otherwise (`Mechanical`, `Default`, or anything else), omit `model` and let the agent's frontmatter `model: sonnet` apply — the workspace env var `ANTHROPIC_DEFAULT_SONNET_MODEL` (see `.claude/settings.json`; currently `claude-sonnet-5[1m]`) resolves it to Sonnet 5 + 1M context. The human can override either direction at the Step 2 gate.

**Which implementer:** dispatch `jiji-<language>-implementer`, where `language` is the value resolved in Step 0 (`rust` → `jiji-rust-implementer`; `js` → `jiji-js-implementer`, the `ff-restore-ext` extension loop). The spec also echoes the language in `## Language`; the registry value is canonical.

**Trailer mode for the implementer's commit(s):** `full-loop` (entering the review cycle).

Invoke the implementer with the confirmed spec. It produces commits at semantic boundaries in `<code_repo>` (the spec's `## Target repo`) and runs the repo's cargo gate.

## Step 4 — Review

Run `/pr-review-toolkit:review-pr` against the new commit(s) in `<code_repo>`.

### Reviewer isolation (mandatory whenever reviewers run in parallel)

**The toolkit provides no isolation of its own.** Its agents carry no `tools:` frontmatter, so every one of them inherits `Edit` / `Write` / `Bash` and can write to whatever tree it is pointed at; nothing in the plugin mentions worktrees. Isolation exists only if *this* step's dispatch text creates it — and the plugin is vendored under `plugins/marketplaces/`, so don't try to fix it there (updates overwrite it).

**Ask reviewers to verify empirically anyway.** Sabotage verification — break the pinned production code, confirm the test fails with the expected message, revert — is what catches the vacuous and false-green pins this codebase keeps producing, and it is worth far more than a passive read. But it makes reviewers *writers*, for minutes at a time, holding source that exists in no commit. Parallel fan-out plus empirical verification is what races; either alone is safe.

**The contract, stated in every reviewer's own prompt:**

- **One private worktree per empirically-verifying reviewer** — `git worktree add ~/.cache/jiji-review-worktrees/wt-<role>-<sha> <sha> --detach`. Per reviewer, **not** per review round: five agents in one shared tree reproduces the race one level down. Detach at the sha (a branch can't be checked out in two worktrees, and the commit under review shouldn't move anyway).
- **Check where you're putting it before you build there.** The session scratchpad lives under `/tmp`, which is commonly a **tmpfs (RAM-backed)** — it is on the maintainer's setup. A `cargo test` tree for this workspace is multi-GB, so several concurrent builds there can exhaust it and pressure the whole system. Confirm with `df -h /tmp <candidate-path>` and prefer real disk (e.g. `~/.cache/…`). Check headroom against `target/` too — a mature checkout's `target/` can dwarf the free space, and every fresh worktree starts from a cold build.
- **Keep the number of building trees small — one or two.** Cold `cargo` builds are the dominant cost of this whole contract, so give a tree only to reviewers whose findings actually depend on running something. If disk is tight, a shared `CARGO_TARGET_DIR` across the trees is a valid fallback: source isolation (the point of the contract) is preserved, at the price of a build lock serializing them and fingerprint thrash between differing sabotage states.
- **Say it is theirs alone**, and require them to restore it clean (`git -C <wt> status --short` empty) before finishing. Tell them explicitly not to touch `<code_repo>`.
- **`git -C <abs-path>` for every git command.** Agent bash cwd resets between calls, so a bare `git status` can silently report on the parent workspace repo and look reassuringly clean.
- **Static-only reviewers get no worktree** — tell them to read via `git show <sha>:<path>` / `git diff <base>..<sha>`, which hit the immutable object store and are immune for free. Comment- and type-design-style reviews usually qualify; anything that builds, runs tests, or instruments a fixture does not. Fewer trees is cheaper: each one is a cold `cargo` build.
- **Remove the worktrees** (`git worktree remove <path> --force`) once the round is done — they don't self-clean, and each carries its own `target/`.

**What a detached worktree keeps and loses** (verified for `repos/jiji` on 2026-07-23 — re-check before assuming it holds for another target, and note some of it is repo-local rather than universal):

- **Kept:** git hooks, including the DD-surrogate-token guard — worktrees share `$GIT_COMMON_DIR/hooks`, so `pre-commit`/`commit-msg`/`check-no-dd-refs.sh` still fire. `build.rs` is git-independent (it only `pkg_config`-probes libinput), so version stamping can't break on a detached HEAD. No submodules, no `rust-toolchain.toml`, no `.cargo/config.toml` — nothing untracked that the build needs.
- **Lost:** `repos/jiji/.claude/` is gitignored, so `settings.local.json` is absent in a worktree; expect permission behavior to differ there. Also note `git worktree add` fires the `post-checkout` hook, which on this repo requires `git-lfs` on `PATH`.
- **LSP/editor tooling** indexes the live checkout, not a `/tmp`-or-cache worktree. That's fine for reviewers (they read the commit and run cargo), but don't expect editor-grade navigation inside one.

**Don't trust a contended tree's cargo results.** A reviewer that saw its tree move must disclaim its build/test output (structural findings grounded in `git show` still stand). Re-run the gate yourself in `<code_repo>` before Step 6 either way — the driver owns the authoritative green, not any reviewer.

## Step 5 — Fixer

Invoke `jiji-fixer` with the review output. The fixer reads the spec's `## Target repo` + that repo's `CLAUDE.md`, classifies findings, and either:

- **Squashes** mechanicals into the reviewed commit via `git commit --amend` (preserves the `full-loop` trailer), when squashing keeps the commit's subject accurate.
- **Creates a follow-up commit** when the finding doesn't fit the reviewed commit's scope. The follow-up uses the same `full-loop` trailer.
- **Escalates** architectural findings back to Step 1 with that as the new `jiji-architect` input (architect produces a follow-up spec, loop continues). This is an *automatic* re-dispatch, so it is resumable in **all modes** (interactive, autonomous main-session, and autonomous `claude -p` loop child): per *Architect resume* above, prefer `SendMessage`-resuming the original `architect-<target>` (by its retained name/`agentId`) with the escalated finding — it retains the sub-phase's full reasoning — and fall back to a fresh dispatch when `SendMessage` is unavailable or the finding is better handled cold.

## Step 5b — Targeted re-review decision

After **every** fixer pass, decide whether the fixer's changes themselves warrant another review round. Default is **skip** — burning another review on trivial edits wastes time. Only re-review when the fixer actually introduced new code surface.

**Skip re-review when all of these hold:**
- Fixer reported a no-op (zero actionable findings).
- No follow-up commit was created.
- Every squashed finding was classified by the fixer as **Mechanical** (renames, message/comment tweaks, `.unwrap()` → `.expect("…")`, typed-error mapping, clippy cleanup, rustdoc fix, single-line log addition, extending an existing test with one more assertion).

**Run a targeted re-review when any of these hold:**
- The fixer created one or more **follow-up commits** (new code/tests landed as their own commit).
- Any squashed finding was a **Scoped addition** (new fixture/queue, new regression test, new helper, new logic surface beyond a single line).

Targeted re-review: invoke `/pr-review-toolkit:review-pr` against **only the fixer's new/amended commit(s)**, under Step 4's *Reviewer isolation* contract (it applies to re-review rounds too — a single re-reviewer still sabotage-verifies, so it still needs its own tree). If clean, continue to Step 6. If findings, loop back to Step 5 with that output as new fixer input.

**Cap at 3 re-review cycles total per sub-phase** (= up to 4 fixer passes). If a 4th would otherwise trigger, stop and raise to the human at Step 6 with a "fixer rounds not converging" note rather than looping further.

Report the decision in one line before proceeding: `Re-review: skipped (all mechanical)` or `Re-review: ran, clean` or `Re-review: ran, fixer loop N`.

## Step 6 — Final-commit gate

**Interactive mode:** stop. Human confirms the amended commit is good and says `scribe` to proceed, or requests revisions.

**Autonomous mode:** pass automatically — *unless* Step 5b reported `fixer rounds not converging` (the round-3 cap was hit). In that case, halt: emit `LOOP_HALT:fixer-cap:<one-line summary of the unresolved finding>` as the final message and end without invoking the scribe. Otherwise, continue to Step 7.

## Step 7 — Scribe

Invoke `jiji-scribe` with input `target=<target>` plus all the sub-phase's commit hashes (amended primary + any follow-ups). The scribe resolves `dd_path` and `dd_commit_repo` from the registry, appends the `Reviewed: YYYY-MM-DD (<hash1>, <hash2>, ...).` paragraph to the target's DD, commits the DD change in `dd_commit_repo` with trailer `AI-Assisted: scribe (<model>)`, and bumps the status doc `specs/<owner>/status.md` Resume cue.

## Step 8 — Report

Output: all `<code_repo>` commit hashes from this sub-phase (amended primary + follow-ups), the DD-scribing commit hash, test pass count delta vs. baseline, next suggested sub-phase (the topmost remaining `[ ]` box).

## Step 8b — Loop signal (autonomous mode only)

In interactive mode, end after Step 8's report — do not emit a `LOOP_*` line.

In autonomous mode, end your final message with **exactly one** of these tokens on its own line, after the report:

- `LOOP_CONTINUE` — sub-phase landed cleanly, next box is unambiguous, no human input required.
- `LOOP_HALT:<reason>` — see triggers below.
- `LOOP_ERROR:<reason>` — irrecoverable failure (build broken on main, dirty tree the implementer can't reconcile, etc.).

Halt triggers (autonomous mode):

- Architect Open questions → `LOOP_HALT:architect-open-questions:<summary>` (raised at Step 2; loop ends before implementer).
- Human-only ratification box reached → `LOOP_HALT:ratification:<box title>` (raised at Step 2).
- Fixer cap hit → `LOOP_HALT:fixer-cap:<summary>` (raised at Step 6; loop ends before scribe).
- DD has no remaining unchecked `[ ]` boxes after the scribe's update → `LOOP_HALT:phase-complete` (raised at Step 8).
- Test count delta unexplained or regressed vs. baseline → `LOOP_HALT:test-delta:<delta>`.
- Any agent escalation that explicitly asks for human judgment beyond the architect's Open questions surface → `LOOP_HALT:decision-needed:<summary>`.

Do NOT call `ScheduleWakeup` in autonomous mode. The orchestrator (`scripts/loop-subphase.sh <target>`) owns iteration cadence — your job is one sub-phase per invocation, plus the signal.
