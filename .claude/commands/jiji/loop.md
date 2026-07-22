---
description: In-session autonomous chain driver for the jiji loop. Spawns scripts/loop-subphase.sh <target> 1 one iteration at a time, summarizing each sub-phase inline and returning to the session on any halt. First arg selects the target from the loop registry.
argument-hint: <target> [max_iter], or --wakeup --log=<marker-path> (re-entry only)
---

`/jiji:loop` runs `scripts/loop-subphase.sh <target> 1` one iteration at a time, driving chain continuation from this slash command instead of from the script's internal `seq` loop:

- Each spawn passes `MAX_ITER=1` to `loop-subphase.sh`, so only one `/jiji:land-subphase --autonomous` iteration is ever in flight. The sub-phase logic stays the single source of truth in `.claude/commands/jiji/land-subphase.md`.
- After an iteration finishes, the chain re-enters via two redundant triggers:
  - **Primary:** the `Bash run_in_background` completion notification (harness-managed, fires the moment the script exits).
  - **Fallback:** a 30-min `ScheduleWakeup` re-invocation of `/jiji:loop --wakeup --log=<marker-path>`. Both triggers depend on the CC session being alive to fire, but they fail independently — the wakeup is here because `ScheduleWakeup` outside the built-in `/loop` skill context is empirically best-effort.
- On each re-entry the chain step is the same: scan the latest chain log for a terminal `Signal:` line → summarize via haiku → spawn the next iter or finalize.

This is jiji's **L3 in-session driver** (see `docs/loops/architecture.md`). Use `/jiji:loop` when starting an autonomous run you want to step away from but still see per-iter summaries on return. Use `scripts/loop-subphase.sh <target> N` directly when you want a quiet multi-iter background run with no in-conversation surface.

## Argument dispatch

Parse `$ARGUMENTS`:

- If `$ARGUMENTS` starts with `--wakeup`, branch to **Re-entry** (Step 5 onward). Extract `--log=<marker-path>` from the args.
- Otherwise branch to **Initial invocation** (Steps 1–4).

The bg-completion notification case routes to the same Step 5 logic but is triggered by a harness event in this conversation rather than by a slash-command re-invocation. Read the marker (path is in conversation context from the last `/jiji:loop` turn; on context loss, fall back to listing `~/.cache/jiji-loop/*.chain` and picking the most recently modified one) and execute Step 5.

## Step 1 — Resolve & clarify (initial invocation)

Parse, in **jiji arg order**: the **first token is `target`** (required); a following **purely-numeric token is `max_iter`** (default 4). The autonomous loop always lands the next unchecked `[ ]` box, so the chain walks consecutive boxes — there is no per-box argument (use interactive `/jiji:land-subphase <target> <box>` to drive one specific box).

Resolve `target` from the workspace root. The resolver merges the public `loops.conf` with the specs overlay (`specs/<owner>/loops.conf`) — never parse either file directly:

```bash
scripts/loops-registry.sh <target> | awk -F'|' '{print "code="$3" dd="$4" ddrepo="$5}'
```

If `target` is missing, or the resolver exits non-zero (1 = unknown, it lists the valid targets; 3 = defined in both registry halves), **stop** and say which. Do not spawn anything, do not call `ScheduleWakeup`.

If `max_iter` was omitted and you can cheaply tell how many `[ ]` boxes remain in the target's `dd_path`, suggest `count + 1` (one extra for halt+resume margin).

## Step 2 — Confirmation gate

Echo the assembled invocation:

```
About to start a chain of up to <max_iter> iterations of
/jiji:land-subphase <target> --autonomous (walking consecutive [ ] boxes).

Each iteration spawns:  scripts/loop-subphase.sh <target> 1  (bg, one iter only)
Chain drivers:          bg-notify (primary) + 30-min ScheduleWakeup (fallback)
Summaries:              one haiku summary per iter, printed inline
Per-iter log:           ~/.cache/jiji-loop/<target>-chain<chain_ts>-iter<N>.log
Chain marker:           ~/.cache/jiji-loop/<target>-chain<chain_ts>.chain (persistent state)

Proceed?
```

One ack. If the user declines, exit cleanly — no spawn, no `ScheduleWakeup`.

## Step 3 — Spawn first iteration

Generate `chain_ts` from `date +%Y%m%d-%H%M%S`. Create `~/.cache/jiji-loop/<target>-chain<chain_ts>.chain` with these lines (one fact per line, trailing newline):

```
chain_ts=<chain_ts>
target=<target>
code_repo=<code_repo from the registry>
dd_path=<dd_path from the registry>
dd_commit_repo=<dd_commit_repo from the registry>
goal_max_iter=<max_iter>
last_summarized_iter=0
last_signal=
latest_log=
```

Spawn the first iteration via `Bash` with `run_in_background: true`:

```
scripts/loop-subphase.sh <target> 1 > ~/.cache/jiji-loop/<target>-chain<chain_ts>-iter1.log 2>&1
```

Immediately update the marker's `latest_log=` line to the per-iter chain log path (`<target>-chain<chain_ts>-iter1.log`). That redirect log is the chain's authoritative source for terminal signals (it captures the script's `tee`'d stdout, including the `Signal:` and `Session:` lines). The script's own internal `${target}-<ts>.log` and per-iter `.json` under the same dir are secondary copies, not tracked by the marker.

## Step 4 — Schedule fallback wakeup

Call `ScheduleWakeup`:

- `delaySeconds`: 1800
- `prompt`: `/jiji:loop --wakeup --log=<marker-path>` (the marker file path, NOT a script log)
- `reason`: `30-min /jiji:loop chain fallback (bg-notify is primary)`

Report to the user:

```
Chain spawned (iter 1/<max_iter> in flight). Primary trigger: bg-completion notify.
Fallback wakeup at HH:MM (in 30 min). Iter summaries print inline as each lands.
Marker: ~/.cache/jiji-loop/<target>-chain<chain_ts>.chain
```

End the turn.

## Step 5 — Re-entry: run the chain step

Triggered by: a bg-completion notification arriving in-conversation, `ScheduleWakeup` firing `/jiji:loop --wakeup --log=<marker-path>`, or the user manually invoking `/jiji:loop --wakeup --log=<marker-path>`.

Read the marker. Extract `chain_ts`, `target`, `code_repo`, `dd_commit_repo`, `goal_max_iter`, `last_summarized_iter`, `latest_log`.

Inspect `latest_log`:

- **Iter completed:** the log carries a terminal `  Signal:` line with `LOOP_CONTINUE` / `LOOP_HALT:*` / `LOOP_ERROR:*`. On a clean continue it also ends with `=== Reached MAX_ITER=1` (the script's wrap-up banner); on halt/error it ends right after the `Resume:` line.
- **Iter still running:** no terminal `Signal:` line for the current iteration yet.

Branch:

- Completed → **Step 5b** (summarize + decide chain progression).
- Still running → **Step 5c** (liveness ping + reschedule fallback).

## Step 5b — Summarize the just-completed iteration

The iteration number is `last_summarized_iter + 1`. Invoke `Agent` with `subagent_type: claude`, `model: haiku`:

```
description: Summarize /jiji:loop iter <N>
prompt: |
    Summarize what landed in iteration <N> of an autonomous /jiji:loop chain. ≤15 lines total.
    Skip ceremony — no review-cycle prose, no agent-dispatch narration.

    Sources (read these and synthesize, in order of authority):
    1. Per-iter chain log: <latest_log path from marker>. Read fully — it carries the
       Signal:, Session:, and Resume: lines verbatim.
    2. Source commits during this iter — run, inside the target's code repo
       (<code_repo from marker>): `git -C <code_repo> log --oneline -8` and keep only
       commits authored during this iteration (match against the log's timestamps).
    3. DD-scribing commit — run `git -C <dd_commit_repo> log --oneline -3` if the
       scribe ran (the chain log's Signal was LOOP_CONTINUE).
    4. Optional: agent's live transcript at the path the log line `Transcript:` records —
       last ~50KB only, and only if the commit list alone doesn't carry the answer.

    Output shape (markdown, ≤15 lines TOTAL):
    - **Iter <N>: <one-line sub-phase title>**
    - If HALTED/ERRORED: lead with the halt reason + one-line "to resume: <what's needed>".
      Then list any commits that DID land, then stop.
    - If completed cleanly: list source commit hashes + one-line subjects (max 5 lines),
      the DD-scribe commit, and the test-count delta vs. baseline if the log shows it.

    Be terse. Reader is returning to the session and wants "what landed" at a glance.
```

If the subagent errors / times out, print one line `[/jiji:loop iter <N>] summary unavailable — <reason>` and continue. Never block the chain on summary success.

Print the summary inline.

Parse the terminal signal from the log. Update the marker (rewrite the file, don't just append):

```
last_summarized_iter=<N>
last_signal=<LOOP_CONTINUE / LOOP_HALT:... / LOOP_ERROR:...>
```

Decide chain progression:

- **`LOOP_CONTINUE` AND N < goal_max_iter** → **Step 5d (spawn next)**.
- **`LOOP_CONTINUE` AND N >= goal_max_iter** → **Step 6 (final, goal reached)**.
- **`LOOP_HALT:*`** → **Step 6 (final, halt)**.
- **`LOOP_ERROR:*`** → **Step 6 (final, error)**.
- **Signal missing/malformed** → **Step 6 (final, missing-signal)**.

## Step 5c — Liveness ping (iter still running)

Print one line:

```
[/jiji:loop liveness HH:MM] iter <N+1>/<goal_max_iter> still running — last completed iter <N>
```

Reschedule the fallback `ScheduleWakeup` with the same args as Step 4 (fresh 1800s, same marker path). End the turn.

## Step 5d — Spawn next iteration

Compute `next_iter = N + 1`. Set `next_log = ~/.cache/jiji-loop/<target>-chain<chain_ts>-iter<next_iter>.log`. Update the marker's `latest_log=` line to `next_log`.

Spawn via `Bash` with `run_in_background: true`:

```
scripts/loop-subphase.sh <target> 1 > <next_log> 2>&1
```

Reschedule fallback `ScheduleWakeup(1800s)` with the same prompt as Step 4. End the turn.

## Step 6 — Final (chain terminated)

Print:

```
[/jiji:loop FINISHED HH:MM] <reason — goal reached / halt:<sub> / error:<sub> / missing-signal>
Chain summary: <last_summarized_iter>/<goal_max_iter> iterations completed.
```

The halt sub-reasons come from `land-subphase.md` / `docs/loops/architecture.md`: `architect-open-questions`, `ratification`, `fixer-cap`, `phase-complete`, `test-delta`, `decision-needed`, plus the script-level `LOOP_ERROR`.

If the terminal signal is `LOOP_HALT:*` requiring a human decision (`architect-open-questions`, `ratification`, `decision-needed`, `fixer-cap`), surface the halt reason verbatim and recommend the next step: resolve the decision here, then resume manually with `claude --resume <session-id>` (from the chain log's `Resume:` line), or drop to interactive `/jiji:land-subphase <target>`. `phase-complete` means the DD has no remaining `[ ]` boxes — report it and stop.

If `LOOP_ERROR:*` or a missing signal, print `Resume: claude --resume <session-id>` using the last iter's session id (parse from the chain log's `Session:`/`Resume:` line).

Append `To push: run /strip-review-needed first.` if any commits landed in the chain.

**Do NOT call `ScheduleWakeup`.** End the turn cleanly.

## Edge cases

- **User asks for status mid-chain:** read the marker, scan the `latest_log`, answer directly. The chain progresses on its own triggers — don't redundantly trigger a chain step from a status request unless the marker shows an unsummarized completion.
- **CC session closes before chain terminates:** the in-flight `loop-subphase.sh` continues to completion. Both triggers need the CC session active to wake the chain step — so after the in-flight iter finishes, no further iters spawn until the user re-attaches with `claude --resume <session-id>` and then manually `/jiji:loop --wakeup --log=<marker-path>`. The chain pauses safely; nothing piles up unattended.
- **Multiple concurrent chains:** each spawns its own chain (distinct `chain_ts`, marker, log paths — and the marker name is target-prefixed). Triggers route by `--log=<marker-path>` in the `ScheduleWakeup` prompt; bg-completion notifications are per-spawn and self-identify.
- **Marker parse failure:** if the marker can't be read or critical keys are missing, print `[/jiji:loop ERROR] marker unreadable; chain abandoned.` Do not reschedule.
- **Heartbeat reliability caveat:** `ScheduleWakeup` outside the built-in `/loop` skill context is best-effort. Both triggers can fail simultaneously; if so the chain pauses (see "session closes" case). The user can manually re-engage at any time.

## What this command does NOT do

- **Modify the sub-phase logic.** It always drives `/jiji:land-subphase <target> --autonomous` via `loop-subphase.sh`; that command stays the single source of truth.
- **Replace `scripts/loop-subphase.sh`.** The detached `seq`-loop remains for quiet no-conversation multi-iter runs. `/jiji:loop` is the in-session, per-iter-surfaced alternative.
- **Push commits or strip `Review-Needed:` trailers.** Both remain manual / use `/strip-review-needed`.
