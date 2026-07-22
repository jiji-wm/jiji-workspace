---
description: Cross-phase cognitive-friction analysis for the jiji compositor and/or CLI loop, followed by cooperative triage with the user, wiring of the scheduled batch (owning DD + loop registry row + status.md), and a launch handoff. Never writes source code; nothing is scheduled without an explicit user decision.
argument-hint: [compositor|cli|both, defaults to compositor]
---

Invoke the `jiji-refactor-pass` subagent, then drive the triage → wiring → launch flow with the user.

Scope: $ARGUMENTS (blank = compositor). Pass the scope word (compositor, cli, or both) to the agent.

**Step 1 — Analysis (agent).** The agent will:
1. Read the workspace CLAUDE.md and `specs/<owner>/status.md` to orient on current phase state.
2. Read the full active DD(s) and landed code in its current state (not just diffs).
3. Read prior refactor-pass and architect-pass docs to avoid re-proposing resolved work.
4. Synthesise proposals ordered by friction-reduction-per-diff-size, each with a **Recommendation** line (schedule/defer/reject — advisory).
5. Write the proposal doc to `specs/<owner>/refactor-passes/YYYY-MM-DD-<scope>.md` with `human-reviewed: false` and commit it.
6. Report back with per-proposal elaborations + recommendations and its handoff text.

No code is written and nothing is scheduled in this step.

**Step 2 — Cooperative triage (user).** Surface the agent's report. Walk the user through the proposals one by one — finding, proposed change, risk, recommendation — and collect a schedule / defer / reject decision for each. A blanket decision ("schedule everything") is valid; if a decision is ambiguous ("the cheap ones"), confirm it per-proposal before proceeding. Do not proceed to Step 3 with any proposal undecided.

**Step 3 — Record + wire (agent, operator-directed).** Relay the user's decisions verbatim to the **same** `jiji-refactor-pass` agent via `SendMessage` resume (available when `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; it is set in `.claude/settings.json` env) — resuming preserves the agent's full analysis context for the wiring. The agent will:
1. Flip the Status checkboxes to match, set `human-reviewed: true`, add a dated triage note, and commit the pass doc (specs repo).
2. For the scheduled set only: author the batch owning DD at `specs/<owner>/<scope>-refactor-YYYY-MM.md` (house-style precedent: the most recent existing batch file there), add the status.md section, add the `refactor`/`refactor-cli` row to the **specs-overlay registry** (`specs/<owner>/loops.conf` — a batch DD lives under `specs/`, so its row never goes in the public workspace `loops.conf`), and commit all three together in the specs repo.
3. Verify the new row resolves: `scripts/loops-registry.sh <row>` prints it and exits 0.

**Fallback (resume unavailable):** perform the same recording + wiring in this session, following the conventions in `.claude/agents/jiji-refactor-pass.md` steps 8–9. Resume is layered, never load-bearing.

**Step 4 — Launch handoff.** Present the exact launch options to the user:
- `/jiji:land-subphase <row>` — interactive, one phase per `go`/`scribe`.
- `/jiji:loop <row> <N>` (or `scripts/loop-subphase.sh <row> <N>` detached) — autonomous chain for the leading mechanical phases.

Include the agent's advice on which phases to keep on the interactive driver (render-path type changes, user-visible ordering transcriptions, anything near an open escalation) and which are safe to chain autonomously. Do not launch anything yourself — the user runs the driver.
