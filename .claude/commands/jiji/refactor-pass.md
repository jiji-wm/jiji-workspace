---
description: Cross-phase cognitive-friction analysis for the jiji compositor and/or CLI loop. Reads landed code in its current state plus surrounding context, emits a proposal doc whose aim is lowering cognitive friction. Never writes source code; human triages before any proposal becomes a scheduled sub-phase.
argument-hint: [compositor|cli|both, defaults to compositor]
---

Invoke the `jiji-refactor-pass` subagent.

Scope: $ARGUMENTS (blank = compositor). Pass the scope word (compositor, cli, or both) to the agent.

The agent will:
1. Read the workspace CLAUDE.md to orient on current phase state.
2. Read the full active DD(s) and landed code in its current state (not just diffs).
3. Read prior refactor-pass and architect-pass docs to avoid re-proposing resolved work.
4. Synthesise proposals ordered by friction-reduction-per-diff-size.
5. Write a proposal doc to `private/docs/refactor-passes/YYYY-MM-DD-<scope>.md` with `human-reviewed: false`.
6. Commit the doc and report back with proposal titles and handoff text.

No code is written. No DDs are modified. The output is a proposal for the human to triage.

After the agent returns, surface its handoff text. The human's next action is reading the doc, marking each `Status:` line (`[x] scheduled / deferred / rejected`), flipping `human-reviewed: false` → `true`, and dropping scheduled proposals into the appropriate loop's DD as new sub-phases.
