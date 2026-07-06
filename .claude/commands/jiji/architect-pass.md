---
description: Cross-phase gap scan for active jiji DDs — reads the design doc and landed commit history, surfaces residual invariant gaps and audit surfaces not covered by any landed phase. Writes a proposal doc to specs/<owner>/architect-passes/.
argument-hint: [compositor|cli, defaults to compositor]
---

Invoke the `jiji-architect-pass` subagent.

Target: $ARGUMENTS (blank = compositor). Pass the target word (compositor or cli) to the agent.

The agent will:
1. Read the workspace CLAUDE.md to orient on phase state.
2. Read the full active design doc and landed commit history.
3. Scan for residual invariant gaps, uncovered mutation entry points, and audit surfaces missed by the per-phase architects.
4. Write a proposal doc to `specs/<owner>/architect-passes/YYYY-MM-DD-<target>.md`.
5. Report the path and a one-paragraph summary.

No code is written. No design doc is modified. The output is a proposal for the human to triage.
