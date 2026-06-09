---
description: Run pr-review-toolkit against HEAD of a jiji target's code repo, then route findings to jiji-fixer. First arg selects the target from loops.conf.
argument-hint: <target>
---

Review the latest commit on a registered loop target and route findings to the fixer.

**Step 0 — Resolve the target.** The first token of `$ARGUMENTS` is the target. Validate it against `loops.conf` (`awk -F'|' '!/^#/ && NF {print $1}' loops.conf`); if absent, stop and report the valid targets. Otherwise read the target's `code_repo` (field 3):

```bash
awk -F'|' -v t="<target>" '!/^#/ && $1==t {print $3}' loops.conf
```

**Step 1:** Run `/pr-review-toolkit:review-pr` against HEAD of `<code_repo>`. The toolkit's orchestrator picks relevant reviewers automatically based on the diff (code-reviewer always; silent-failure-hunter when error-handling changes; comment-analyzer when comments/docstrings change; pr-test-analyzer when tests change; type-design-analyzer when new types are introduced).

**Step 2:** Once review output is available, invoke the `jiji-fixer` subagent with that output. The fixer reads the spec's `## Target repo` + that repo's `CLAUDE.md` for classification context, then:

- **Classifies each finding** as mechanical / scoped addition / architectural / debatable / park.
- **Applies mechanicals and scoped additions** either by squashing into the reviewed commit via `git commit --amend` (preserving the existing `AI-Assisted:` trailer) or by creating a **follow-up commit** when squashing would misrepresent the reviewed commit's subject.
- **Escalates architectural findings** back to the architect — the human should then run `/jiji:next-subphase <target> <the escalated concern>` to continue the loop with a follow-up spec.
- **Reports debated findings** to the human without acting.
- **Surfaces meta-learning hints** when findings look like recurring patterns — the human decides whether to codify them in `jiji-rust-implementer.md` / `jiji-architect.md` (not the fixer's job, not applied automatically).
- **Short-circuits on zero actionable findings** — no amend, no follow-up, reports no-op.

The amend (if any) changes the commit hash; follow-up commits are separate hashes. Report all hashes — the scribe will update the DD hash reference in the review-scribing commit.
