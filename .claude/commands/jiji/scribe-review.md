---
description: Append a Reviewed: entry to a jiji target's DD for one or more landed commits via jiji-scribe. First arg selects the target from loops.conf.
argument-hint: <target> [space-separated commit hashes, or blank for HEAD of the code repo]
---

Scribe a Reviewed: entry into a registered loop target's DD.

**Step 0 — Resolve the target.** The first token of `$ARGUMENTS` is the target. Validate it against `loops.conf` (`awk -F'|' '!/^#/ && NF {print $1}' loops.conf`); if absent, stop and report the valid targets. Otherwise bind the target's `code_repo` (field 3); the scribe resolves `dd_path` and `dd_commit_repo` itself. Strip the target token; the remainder is the commit hash list.

Commit(s) to document: the post-target remainder of `$ARGUMENTS` (if blank, HEAD of `<code_repo>`; if multiple, treat them as one sub-phase's primary + follow-ups).

Invoke the `jiji-scribe` subagent with input `target=<target>` plus the commit hash(es). The scribe will:

1. Read the commit(s) (`git -C <code_repo> show <hash>`) plus the review output and fixer's report from the current conversation.
   - **If run in a fresh session with no review output in context** (e.g., after `/clear`): fall back to `git show <hash>` + the DD's prior `Reviewed:` blocks (or the sibling DD's, if this is the DD's first Reviewed: block). Note in the new paragraph that review findings were not available mid-session, and cite only what the commits themselves demonstrate.
2. Resolve `dd_path` and `dd_commit_repo` from `loops.conf`, and read the most recent two to three `Reviewed:` blocks in the target's DD (or the sibling DD if this is its first block) to match voice.
3. Flip the relevant checkboxes and append the `**Reviewed:** YYYY-MM-DD (<hash1>[, <hash2>, ...]).` paragraph citing all hashes passed.
4. Commit the DD change in `dd_commit_repo` (staging only the DD file so the commit-msg hook's `EXEMPT_PATHS` exemption applies), trailer `AI-Assisted: scribe (<model>)`, and bump the status doc `specs/<owner>/status.md` Resume cue.
