# jiji DD-loop — developer's guide

A practical reference for using the unified `jiji-*` subagents and flat `/jiji:*` slash commands to land sub-phases from any loop target's DD.

**One loop, many targets.** A single role-based agent set (`jiji-architect`, `jiji-<language>-implementer`, `jiji-fixer`, `jiji-scribe`) drives every target. The first argument to each command is a **`<target>`** — a name registered in **`loops.conf`** (`name|language|code_repo|dd_path|dd_commit_repo`). **The authoritative target registry is `loops.conf`** — check it for the current list rather than any snapshot here. Two illustrative rows:

| target | language | code repo | DD | DD commit repo |
|---|---|---|---|---|
| `compositor` | rust | `repos/jiji` | `specs/<owner>/activities/design.md` | specs overlay (`specs`) |
| `cli` | rust | `repos/jiji-activities` | `repos/jiji-activities/docs/design.md` | `repos/jiji-activities` |

The command resolves the target against `loops.conf`, dispatches `jiji-<language>-implementer` (`rust` → `jiji-rust-implementer`, `js` → `jiji-js-implementer`), and the scribe commits the DD change in the target's `dd_commit_repo`. **Per-codebase discipline lives in each target repo's `CLAUDE.md`** — the compositor's invariant-check + test-bucket arithmetic in `repos/jiji/CLAUDE.md`, the CLI's `assert_cmd`/exit-code/fuzzel rigor in `repos/jiji-activities/CLAUDE.md`, the extension's marker/protocol contracts in `repos/jiji-firefox-workspaces/extension/CLAUDE.md`. The agents read it; they don't bake it.

**Shared DDs (multi-loop).** Usually two targets never share an active DD. Occasionally they do — e.g. `ff-restore` + `ff-restore-ext`: one design doc split by component + language (Rust host in `src/`, JS extension in `extension/`); `loops.conf` comments mark the shared rows. The checklist tags each box with its owning loop, and the architect plans only its loop's boxes. **When landing against a shared DD, always name the box** (e.g. `/jiji:land-subphase ff-restore-ext P4`) so the architect plans the right one.

## TL;DR

For routine sub-phase work, run:

    /jiji:land-subphase <target>

Stop at the two human gates. Say `go` to pass the first, `scribe` to pass the second. End state: one or more code commits in the target's `code_repo` (usually one; occasionally a primary + follow-up when review surfaces something outside the primary commit's scope), one DD commit in the target's `dd_commit_repo`.

## The five commands

| Command | When to use | What it runs |
|---|---|---|
| `/jiji:next-subphase <target> [name]` | You want to see a spec only, not implement yet | jiji-architect |
| `/jiji:implement <target>` | You have a spec and want to code it *without* review | jiji-\<language\>-implementer |
| `/jiji:apply-review <target>` | HEAD commit in the code repo needs review + fixer | `/pr-review-toolkit:review-pr` + jiji-fixer |
| `/jiji:scribe-review <target> [hash]` | Review is done; append the `Reviewed:` block to the DD | jiji-scribe |
| `/jiji:land-subphase <target> [name]` | **Default.** Full architect → implementer → review → fixer → scribe cycle | all four, in sequence |

`[name]` defaults to "topmost unchecked `[ ]` box in the current phase" when blank. `[hash]` defaults to HEAD of the target's `code_repo`. The orchestrator (`scripts/loop-subphase.sh <target> [N]`) drives `/jiji:land-subphase <target> --autonomous` in fresh `claude -p` sessions and validates `<target>` against `loops.conf`.

## Human-only ratification boxes (no code)

Some DDs front a phase with **design-ratification** boxes — human-confirmed decisions against the DD's `**Proposed:**` recommendations, not implementation:

- `jiji-architect` detects a ratification target and STOPs without producing a spec — there's nothing to compile against an unratified decision.
- Resolve it by editing the DD directly: flip `[ ]` → `[x]` for ratified items, optionally with an amendment line.
- Commit the DD edit in the target's `dd_commit_repo` with a subject like `docs: <dd-name> — ratify <boxes>`.
- Then re-run `/jiji:next-subphase <target>` (or `/jiji:land-subphase <target>`) — the architect picks up the next implementable box.

The architect refuses to plan implementable work until the ratification boxes are `[x]`. This is intentional: spec'ing against a not-yet-ratified strategy produces a spec that has to be redone if the ratification amends. (In autonomous mode this surfaces as `LOOP_HALT:ratification:<box>`.)

## Typical full-loop walkthrough

Starting clean with `/jiji:land-subphase <target>`:

### 1. Kick it off
    /jiji:land-subphase <target>

### 2. Architect produces spec
Output carries the routing metadata (`## Language`, `## Target repo`) plus scope, out-of-scope, invariants touched, hazards (lifted from the target repo's `CLAUDE.md`), test impact, commit boundary, and any DD-updates / open-questions. Run stops at the first human gate.

### 3. **Human gate 1** — spec review
- Spec looks good → say `go`.
- "Open questions" non-empty → answer them, then say `go`.
- Spec is too thin or wrong scope → ask the architect to refine specific parts.

### 4. Implementer produces code + commit(s)
`jiji-<language>-implementer` writes to the target's `code_repo`, runs the repo's gate (`cargo +nightly fmt` apply → `cargo check` / clippy / the repo's test command → `fmt -- --check` gate), and produces the commit(s) the spec's Commit boundary calls for with trailer `AI-Assisted: full-loop (<model>)`. Reports all hashes, pass count (in the repo's reporting convention), clippy delta.

### 5. Review fans out automatically
`/pr-review-toolkit:review-pr` picks relevant reviewers based on the diff. Consolidated findings report returned.

### 6. Fixer applies findings
`jiji-fixer` reads the spec's `## Target repo` + that repo's `CLAUDE.md` for classification context, then for each finding chooses **squash** (amend into the reviewed commit, preserving the `full-loop` trailer) or **follow-up** (new commit, same trailer) — test: *would the reviewed commit's subject still describe all its changes after squashing this in?* Architectural findings escalate back to `jiji-architect` (loop back to step 1 as a "Follow-up spec"). Reports all applied / escalated / debated / parked findings, plus the final hashes.

### 7. **Human gate 2** — confirm amended commit
- OK → say `scribe`.
- Wants more work → ask for specific changes, or escalate back to the architect.

### 8. Scribe updates the DD
`jiji-scribe` resolves `dd_path` + `dd_commit_repo` from `loops.conf`, reads the most recent two-to-three `Reviewed:` blocks to match voice, flips checkboxes, appends the `Reviewed:` paragraph citing all sub-phase commits (primary + any follow-ups), commits in `dd_commit_repo` with trailer `AI-Assisted: scribe (<model>)`, and bumps the workspace `CLAUDE.md` Resume cue.

### 9. Report
All `code_repo` commit hashes from this sub-phase, the DD-scribing commit hash, test pass count delta, next suggested sub-phase.

## Common scenarios

### "Just plan, don't commit anything"
    /jiji:next-subphase <target>

### "Bad spec, architect try again"
After the architect's output, name the gap concretely (a missed call site, a wrong scope split, a missing exit-code or invariant the target repo's `CLAUDE.md` calls for). Iterate — don't type `go` until the spec is right.

### "Architect bundled a substantive mechanical with a Default box"
Watch for this at gate 1: the spec's `## Scope` bundles a large mechanical change with an invariant/contract-adding box, so `## Complexity` is `Default`. If the mechanical portion is large enough that the cheaper model would save meaningful tokens, push back and have the architect split it into two specs. The rule lives in the architect prompt (commit-sizing rule (d)); this gate is the fallback.

### "Trivial commit, skip the review"
    /jiji:implement <target>

Implementer commits with `AI-Assisted: implementer (<model>)`.

### "Review escalated something architectural"
Loop back:
    /jiji:next-subphase <target> <the thing that needs re-planning>

### "Architect found an architectural problem in the DD itself"
The architect puts the issue in its `## Open questions` section and stops — do *not* say `go`. Resolve the DD question first (typically a standalone DD-fix commit in the target's `dd_commit_repo`), then re-run `/jiji:next-subphase <target>`. The softer `## DD updates proposed` section is different — editorial/structural edits that don't block planning; the scribe applies them at end of loop, and the human only glances at them at Gate 1.

### "Review surfaced a finding that doesn't fit the reviewed commit"
The fixer chooses automatically: **squash** if the fix is a correction to what the commit already does, **follow-up** if it's semantically separate (a regression test *for* the change, post-main polish, a pre-existing parallel bug).

### "The fixer flagged a meta-learning hint"
The fixer's report may end with a "Meta-learning hints" section pointing at a recurring pattern the `jiji-rust-implementer` or `jiji-architect` prompt should codify. Decide if it's a real pattern (not a one-off) and edit the agent file yourself — the fixer deliberately doesn't touch agent prompts. Land the tweak as its own commit. (Codebase-specific recurrences belong in the target repo's `CLAUDE.md` instead, since that's where per-codebase discipline lives.)

### "Review already ran manually, now just scribe it"
    /jiji:scribe-review <target> [hash]

### "Need a dependency/rev bump for a new fork variant (cli target)"
That's its own sub-phase. The implementer lands a rev bump as a standalone commit before any code that wraps the new variant. Bump first → verify `cargo check` → land. Then plan the wrapping work as a normal sub-phase against the new rev. (The exact discipline is in `repos/jiji-activities/CLAUDE.md`.)

### "Started from a stale spec after a day away"
Don't. `/clear` first, then run `/jiji:next-subphase <target>` fresh. Long-context retrieval on Opus 4.7 is noticeably worse than 4.6; don't let sessions sprawl.

## Cost / effort quick reference

| Agent | Model | Effort | Why |
|---|---|---|---|
| jiji-architect | opus | xhigh | Planning is where deep reasoning pays off; it's the loop's quality gatekeeper |
| jiji-\<language\>-implementer | sonnet[1m] | *(frontmatter default)* | Spec front-loads the reasoning; execution is mostly mechanical. Escalates to opus only on `## Complexity: Deep` |
| jiji-fixer | sonnet | *(frontmatter default)* | Mechanical squash is cheap |
| jiji-scribe | sonnet | *(frontmatter default)* | Voice is well-established, pattern-matching |

`sonnet` resolves to `claude-sonnet-4-6[1m]` (Sonnet 4.6 + 1M context) via the workspace env var `ANTHROPIC_DEFAULT_SONNET_MODEL`. Only the implementer's *model* is chosen per-spec by the command (from the `## Complexity` token: `Deep` → opus, else sonnet); `effort` is governed only by frontmatter. The architect is the only `xhigh` consumer in a typical run.

**Cut implementer to sonnet** is the default; **escalate to opus** is automatic when the architect tags `## Complexity: Deep` (genuinely hard reasoning the spec can't pre-resolve). Manual override at gate 1 (`go, but use opus` / `go, but use sonnet`) if you disagree with the tag. Don't cut the architect.

## Trailer modes

| Flow | Code commit trailer | DD commit trailer |
|---|---|---|
| `/jiji:land-subphase <target>` (full loop) | `full-loop (<model>)` | `scribe (<model>)` |
| `/jiji:implement <target>` alone | `implementer (<model>)` | — |
| Manual edits, drive-by | `one-shot (<model>)` | `one-shot (<model>)` |

`Review-Needed: committed by Claude Code` goes on every commit; strip when reviewed. `AI-Assisted: ...` is permanent.

## Files in `.claude/`

```
.claude/
  agents/
    jiji-architect.md          # planner; opus/xhigh; resolves target via loops.conf
    jiji-rust-implementer.md   # Rust coder; sonnet; reads target repo CLAUDE.md
    jiji-fixer.md              # mechanical fixes; sonnet
    jiji-scribe.md             # DD ledger; sonnet; resolves dd_commit_repo via loops.conf
    jiji-architect-pass.md     # cross-phase gap analysis  → /jiji:architect-pass
    jiji-refactor-pass.md      # cross-phase friction scan  → /jiji:refactor-pass
  commands/
    jiji/
      next-subphase.md   # plan only          → /jiji:next-subphase <target>
      implement.md       # code only          → /jiji:implement <target>
      apply-review.md    # review + fixer     → /jiji:apply-review <target>
      scribe-review.md   # append Reviewed:   → /jiji:scribe-review <target>
      land-subphase.md   # full orchestrator  → /jiji:land-subphase <target>
      architect-pass.md  refactor-pass.md  initiative.md   # cross-loop
  settings.local.json          # personal (gitignored)
  scheduled_tasks.lock         # runtime (gitignored)
```

Adding a loop target is one `loops.conf` row (plus, only for a genuinely new language, one `jiji-<language>-implementer`).

## Gotchas

- **Amend changes the hash.** When the fixer amends, HEAD's hash changes. The scribe writes the Reviewed: block against the post-amend hash. Don't push between amend and scribe.
- **Two repos for the `cli` target.** Its code commits and DD commit both land in `repos/jiji-activities`, but the workspace `CLAUDE.md` Resume-cue edit lands in the workspace repo — so the scribe produces commits in two repos. For the `compositor` target (`dd_commit_repo` = `.`), DD and Resume-cue edits both live in the workspace, as separate commits.
- **Per-codebase baselines live in the target repo's `CLAUDE.md`.** Test counts and clippy baselines (compositor's four-bucket arithmetic; the CLI's count) are tracked there, not here. If a count drifts unexpectedly, investigate before committing — an unexplained delta is a stop-and-report condition.
- **Voice consistency.** The DDs are read alongside each other. Scribes match the existing `Reviewed:` voice exactly.
- **`/clear` between sub-phases.** Opus 4.7's long-context retrieval regression is real; don't let sessions sprawl across multiple sub-phases. The orchestrator's fresh-`claude -p`-per-iteration design exists for the same reason.
