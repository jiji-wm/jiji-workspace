---
description: jiji loop — architect plans, human confirms, implementer codes, review runs, fixer cleans up, scribe documents. First arg selects the target from loops.conf.
argument-hint: <target> [--autonomous] [sub-phase name]
---

Full sub-phase landing loop for any registered jiji loop target. One agent set serves every target; the **language** (resolved from `loops.conf`) chooses which implementer runs.

## Step 0 — Resolve the target

Parse `$ARGUMENTS`: the **first token is the target** (e.g. `compositor`, `cli`). Validate it against `loops.conf` at the workspace root:

```bash
awk -F'|' -v t="<target>" '!/^#/ && $1==t {print "lang="$2" code="$3" dd="$4" ddrepo="$5}' loops.conf
```

If the target is not in `loops.conf`, **stop** and report the valid targets (`awk -F'|' '!/^#/ && NF {print $1}' loops.conf`). Otherwise bind `language` (field 2), `code_repo` (field 3) for this run. Strip the target token from `$ARGUMENTS`; the remainder (after also stripping a leading `--autonomous`) is the sub-phase name passed to the architect.

## Invocation modes

Selected by the post-target remainder of `$ARGUMENTS`:

- **Interactive** (default): human gates at Step 2 (after architect spec) and Step 6 (after fixer). Human types `go` / `scribe` to proceed.
- **Autonomous** (when the remainder starts with `--autonomous`, optionally followed by a sub-phase name): no human gates. Steps 2 and 6 pass automatically *unless* a halt condition fires. End the final message with a single `LOOP_*` signal line for the orchestrator. Designed for `claude -p` invocation from `scripts/loop-subphase.sh <target>`.

The mode only affects Steps 2, 6, and 8 — Steps 1, 3, 4, 5, 5b, 7 are identical. **Do not call `ScheduleWakeup`** in autonomous mode; the orchestrator owns iteration cadence.

## Step 1 — Architect

Invoke `jiji-architect` with input `target=<target> sub-phase=<remainder>` (blank remainder = next unchecked `[ ]` box in the current phase, then scan ahead and combine consecutive boxes into one landing unit per the grouping criteria). The architect resolves the target's DD and `<code_repo>/CLAUDE.md` itself and produces a spec per its output format, carrying `## Language` and `## Target repo` routing metadata.

**Human-only ratification special-case:** if the next unchecked box is a human-only design-ratification box, the architect will STOP without producing a spec — those boxes are human-only DD decisions. Resolve them by editing the target's DD directly (flip `[ ]` → `[x]` per ratification, optionally with an amendment note), commit, then re-run `/jiji:next-subphase <target>` or `/jiji:land-subphase <target>`.

## Step 2 — Spec gate

**Interactive mode:** stop and wait for human review of the spec. Human says `go` to proceed, or asks the architect to revise.

**Autonomous mode:** pass automatically — but inspect the architect's output first:

- If the architect's **`## Open questions`** section is non-empty, halt: emit `LOOP_HALT:architect-open-questions:<one-line summary>` as the final message and end. Do not invoke the implementer. (Open questions are reserved for architectural questions with no clear technical winner — UX policy, cross-loop coordination, backwards-compatibility — that genuinely need human judgment. Editorial and architecturally-resolvable DD issues are landed by the architect itself before producing the spec; they show up in `## DD updates landed`, not here.)
- If the architect stopped without producing a spec because the next box is a **human-only ratification box**, halt: emit `LOOP_HALT:ratification:<box title>` and end. Those boxes are human-only DD decisions.
- If the architect's **`## DD updates landed`** section is non-empty, this is informational — the architect has already committed DD edits to resolve editorial or architecturally-resolvable questions. Continue.
- If the architect's **`## DD updates proposed`** section is non-empty, this is non-blocking — the scribe folds the edits in at end of loop. Continue.

## Step 3 — Implementer

**Model selection:** read the spec's `## Complexity` section. If its first non-blank token is `Deep`, invoke the implementer with `model: "opus"` (Opus 4.7, 1M context). Otherwise (`Mechanical`, `Default`, or anything else), omit `model` and let the agent's frontmatter `model: sonnet` apply — the workspace env var `ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-4-6[1m]` resolves it to Sonnet 4.6 + 1M context. The human can override either direction at the Step 2 gate.

**Which implementer:** dispatch `jiji-<language>-implementer`, where `language` is the value resolved in Step 0 (`rust` → `jiji-rust-implementer`; `js` → `jiji-js-implementer`, the `ff-restore-ext` extension loop). The spec also echoes the language in `## Language`; the registry value is canonical.

**Trailer mode for the implementer's commit(s):** `full-loop` (entering the review cycle).

Invoke the implementer with the confirmed spec. It produces commits at semantic boundaries in `<code_repo>` (the spec's `## Target repo`) and runs the repo's cargo gate.

## Step 4 — Review

Run `/pr-review-toolkit:review-pr` against the new commit(s) in `<code_repo>`.

## Step 5 — Fixer

Invoke `jiji-fixer` with the review output. The fixer reads the spec's `## Target repo` + that repo's `CLAUDE.md`, classifies findings, and either:

- **Squashes** mechanicals into the reviewed commit via `git commit --amend` (preserves the `full-loop` trailer), when squashing keeps the commit's subject accurate.
- **Creates a follow-up commit** when the finding doesn't fit the reviewed commit's scope. The follow-up uses the same `full-loop` trailer.
- **Escalates** architectural findings back to Step 1 with that as the new `jiji-architect` input (architect produces a follow-up spec, loop continues).

## Step 5b — Targeted re-review decision

After **every** fixer pass, decide whether the fixer's changes themselves warrant another review round. Default is **skip** — burning another review on trivial edits wastes time. Only re-review when the fixer actually introduced new code surface.

**Skip re-review when all of these hold:**
- Fixer reported a no-op (zero actionable findings).
- No follow-up commit was created.
- Every squashed finding was classified by the fixer as **Mechanical** (renames, message/comment tweaks, `.unwrap()` → `.expect("…")`, typed-error mapping, clippy cleanup, rustdoc fix, single-line log addition, extending an existing test with one more assertion).

**Run a targeted re-review when any of these hold:**
- The fixer created one or more **follow-up commits** (new code/tests landed as their own commit).
- Any squashed finding was a **Scoped addition** (new fixture/queue, new regression test, new helper, new logic surface beyond a single line).

Targeted re-review: invoke `/pr-review-toolkit:review-pr` against **only the fixer's new/amended commit(s)**. If clean, continue to Step 6. If findings, loop back to Step 5 with that output as new fixer input.

**Cap at 3 re-review cycles total per sub-phase** (= up to 4 fixer passes). If a 4th would otherwise trigger, stop and raise to the human at Step 6 with a "fixer rounds not converging" note rather than looping further.

Report the decision in one line before proceeding: `Re-review: skipped (all mechanical)` or `Re-review: ran, clean` or `Re-review: ran, fixer loop N`.

## Step 6 — Final-commit gate

**Interactive mode:** stop. Human confirms the amended commit is good and says `scribe` to proceed, or requests revisions.

**Autonomous mode:** pass automatically — *unless* Step 5b reported `fixer rounds not converging` (the round-3 cap was hit). In that case, halt: emit `LOOP_HALT:fixer-cap:<one-line summary of the unresolved finding>` as the final message and end without invoking the scribe. Otherwise, continue to Step 7.

## Step 7 — Scribe

Invoke `jiji-scribe` with input `target=<target>` plus all the sub-phase's commit hashes (amended primary + any follow-ups). The scribe resolves `dd_path` and `dd_commit_repo` from `loops.conf`, appends the `Reviewed: YYYY-MM-DD (<hash1>, <hash2>, ...).` paragraph to the target's DD, commits the DD change in `dd_commit_repo` with trailer `AI-Assisted: scribe (<model>)`, and bumps the status doc `private/docs/status.md` Resume cue.

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
