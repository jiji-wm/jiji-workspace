---
name: strip-review-needed
description: >
  Strip `Review-Needed:` trailers from already-reviewed commits. Trigger on
  /strip-review-needed, "remove Review-Needed trailer", "strip review trailers",
  or after the user has finished reviewing a batch of AI-assisted commits.
  Mechanical operation — keeps `AI-Assisted:` (the permanent audit trail)
  intact. Refuses to rewrite already-pushed commits unless explicitly forced.
argument-hint: "[<range>] [--apply] [--force]"
---

# Strip Review-Needed trailers

Bulk-strips `Review-Needed: committed by Claude Code` from a range of commits.
Keeps `AI-Assisted:` (permanent audit trail) and any other trailers untouched.
The actual edit is `git filter-branch --msg-filter` with a single-line `sed` —
no LLM judgment involved.

## When to use

After the user has reviewed a batch of AI-assisted commits and is ready to
clear the `Review-Needed:` trailers. Per workspace `CLAUDE.md`:

> `Review-Needed:` commits should not be pushed. The default expectation is
> that the trailer is stripped before any push — after I've reviewed the
> commit myself, or when I explicitly authorize Claude to rewrite.

This skill automates that strip step.

## Default range

`@{upstream}..HEAD` — only unpushed commits.
Falls back to `main..HEAD` (then `master..HEAD`) when no upstream is configured.

## Safety

- **Refuses to rewrite already-pushed commits** unless `--force` is passed.
  (When `--force` is used, the caller must follow up with
  `git push --force-with-lease` themselves — the script does not push.)
- **Aborts on a dirty worktree.** Stash or commit first.
- **Does not push** under any circumstances.
- **Preview by default.** Without `--apply`, prints what *would* be rewritten
  and exits 0. Re-run with `--apply` to actually rewrite.

## Procedure for the agent

1. Pick the repo: run from inside the target nested repo (`cd repos/jiji` or
   `cd repos/jiji-activities/`, or the absolute path `$CLAUDE_PROJECT_DIR/repos/jiji-activities/`, etc.) before invoking the script.
2. Run preview: `bash $CLAUDE_PROJECT_DIR/tools/strip-review-needed/strip.sh "$@"`.
3. Show the preview output to the user verbatim. Ask for explicit "yes" before
   proceeding.
4. On confirmation, re-run with `--apply` appended.
5. If `--force` was used, remind the user that
   `git push --force-with-lease` is the next step. Do **not** run it.

## Usage forms

```bash
# From inside a nested repo (e.g. repos/jiji):
bash $CLAUDE_PROJECT_DIR/tools/strip-review-needed/strip.sh           # preview, default range
bash $CLAUDE_PROJECT_DIR/tools/strip-review-needed/strip.sh --apply   # rewrite
bash $CLAUDE_PROJECT_DIR/tools/strip-review-needed/strip.sh HEAD~5..HEAD
bash $CLAUDE_PROJECT_DIR/tools/strip-review-needed/strip.sh --apply --force
```
