---
description: Implement the current jiji-architect spec via jiji-<language>-implementer (standalone, no review loop). First arg selects the target from the loop registry.
argument-hint: <target>
---

Implement the most recent `jiji-architect` spec for a registered loop target, without the review/fixer/scribe loop.

**Step 0 — Resolve the target.** The first token of `$ARGUMENTS` is the target. Resolve it with `scripts/loops-registry.sh` (which merges the public `loops.conf` with the specs overlay — never parse either file directly); on a non-zero exit, stop and report why (exit 1 unknown target, exit 3 defined in both halves). Otherwise read the target's `language` (field 2):

```bash
scripts/loops-registry.sh <target> | awk -F'|' '{print $2}'
```

Invoke the `jiji-<language>-implementer` subagent (`jiji-rust-implementer` or `jiji-js-implementer`) with the spec from the most recent `jiji-architect` output visible in this conversation's context. The spec's `## Target repo` names where source lands; `## Language` should match the registry value (the registry is canonical).

**Trailer mode for the commit:** `implementer` (this is a standalone call; no `/jiji:apply-review` + `/jiji:scribe-review` follows automatically).

The implementer will:
1. Re-read the spec; escalate to `jiji-architect` if anything is unclear.
2. Read the target repo's `CLAUDE.md` for codebase discipline.
3. Produce the commit(s) the spec's `## Commit boundary` calls for — usually one for a standalone `/jiji:implement` call — in the target's `code_repo`, trailer `AI-Assisted: implementer (<model>)`.
4. Run the repo's cargo gate (`fmt` / `check` / `clippy` / test) and report results.

If you want the full loop (review + fixer + scribe) instead, use `/jiji:land-subphase <target>`.
