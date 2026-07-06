---
description: Query or update the jiji launcher initiative. Modes: status (default), or free-form prompt for initiative management.
argument-hint: [status | note <text> | done <stage-name> <commit-hash>]
---

Read and interact with the jiji launcher initiative at `specs/<owner>/launcher/initiative.md`.

Parse `$ARGUMENTS`:

- Blank or `status` → emit a concise status summary: which stages are done, which are in flight, which are blocked, what the next unblocked action is. Read `specs/<owner>/launcher/initiative.md` plus the status doc `specs/<owner>/status.md`. Do not modify any files.

- `note <text>` → append a dated note to `specs/<owner>/launcher/initiative.md` under a `## Notes` section (create it if missing). Commit the change in the workspace repo with subject `docs(launcher): add note` and trailers `Review-Needed: committed by Claude Code` and `AI-Assisted: one-shot (<model>)`.

- `done <stage-name> <hash>` → update stage `<stage-name>` in `specs/<owner>/launcher/initiative.md` to mark it complete, recording the commit hash. Commit in the workspace repo with subject `docs(launcher): mark <stage-name> done` and appropriate trailers.

- Any other text → treat as a free-form prompt: read `specs/<owner>/launcher/initiative.md` and respond based on the user's question or instruction. For file modifications, commit with appropriate trailers.
