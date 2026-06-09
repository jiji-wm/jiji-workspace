---
description: Plan the next DD sub-phase for a jiji loop target using jiji-architect. First arg selects the target from loops.conf.
argument-hint: <target> [sub-phase name, or blank for "next unchecked box"]
---

Plan the next sub-phase for a registered jiji loop target.

**Step 0 — Resolve the target.** The first token of `$ARGUMENTS` is the target (e.g. `compositor`, `cli`). Validate it against `loops.conf` at the workspace root:

```bash
awk -F'|' '!/^#/ && NF {print $1}' loops.conf
```

If the target is absent, stop and report the valid targets. Otherwise strip the target token; the remainder is the sub-phase name.

Invoke the `jiji-architect` subagent with input `target=<target> sub-phase=<remainder>`. It resolves the target's `language`, `code_repo`, and `dd_path` from `loops.conf`, reads `<code_repo>/CLAUDE.md` for hazards, and (if the remainder is blank) picks the topmost unchecked `[ ]` box, scanning ahead to combine consecutive qualifying boxes into one landing unit.

**Human-only ratification special-case:** if the next unchecked box is a human-only design-ratification box, the architect will STOP without producing a spec — those are human-only DD decisions. Resolve them by editing the target's DD directly and committing, then re-run.

Otherwise: the architect produces a spec per its output format (with `## Language` + `## Target repo` routing metadata). After output, stop and wait for human confirmation before any code is written.
