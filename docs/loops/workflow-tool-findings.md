# Claude Code Workflow tool — capabilities, limits, and why jiji uses a conversational loop

**Status:** Findings, 2026-06-19. Empirically verified in-session (CLI v2.1.183) unless marked *inferred*.
**Why this exists:** `/jiji:flow` was built as a `Workflow`-tool driver for the autonomous loop and **could not run**. This documents exactly why, what the Workflow tool can and cannot do, and the decision to retire the workflow driver in favour of a conversational `/jiji:loop` (ported from a battle-tested loop driver in a sibling workspace). Read this before proposing any Workflow-tool-based orchestration for the loop.

---

## 0. The loop is a three-layer cake (only L3 was ever in question)

| Layer | Component | Role |
|---|---|---|
| **L1** | `.claude/commands/jiji/land-subphase.md` (`--autonomous`) | per-sub-phase state machine: architect → spec gate → implementer → review → fixer → re-review → scribe. Sole external contract: a final `LOOP_CONTINUE` / `LOOP_HALT:<reason>` / `LOOP_ERROR:<reason>` line. **Single source of truth for batch logic.** |
| **L2** | `scripts/loop-subphase.sh <target> [N]` | detached Bash loop running `claude -p "/jiji:land-subphase --autonomous"` once per iteration. Fresh process per iter = cold cache = peak reasoning. Robust, quiet, no conversation surface. |
| **L3** | the in-session driver | runs L2 one iteration at a time from a live session, surfacing per-iter summaries and halts. **This is the only layer the workflow experiment touched.** |

`/jiji:flow` tried to be L3 as a `Workflow`. This doc is about why that failed and what L3 should be instead.

---

## 1. A Workflow-spawned subagent CANNOT dispatch a further subagent  *(verified)*

The `Workflow` tool runs a JS script whose `agent()` calls spawn subagents. Those subagents have **no agent-spawning tool** — not `Agent`, not `Task`, nothing — **even with `agentType:'general-purpose'` (`Tools:*`)**. The wildcard does **not** survive nesting; the harness strips agent-dispatch from any context that is itself a subagent (a recursion guard).

- **Probe:** a workflow spawned one `general-purpose` agent and asked it to dispatch a trivial sub-subagent. Result: `dispatchToolListed:false` — four `ToolSearch` queries (incl. exact `select:Agent,Task,TaskCreate`) found nothing.
- **Consequence:** the "thin driver" shape — one subagent *reads `land-subphase.md` and fans out to the role agents* — is **impossible**. This is exactly how `/jiji:flow` was built, which is why it failed instantly with `no-subagent-dispatch-tool`.
- **Corollary:** a multi-agent *skill* (e.g. `/pr-review-toolkit:review-pr`, which itself fans out to code-reviewer / silent-failure-hunter / …) **cannot be invoked from a leaf agent**. Any workflow review step must reproduce that fan-out in the script.

The **only** context that can dispatch agents is the **workflow script itself (level 0)**.

## 2. The only viable workflow shape is "full orchestrator" (1b) — at the cost of a second source of truth

Because only the script can dispatch, a working workflow must call each role directly: `agent({agentType:'jiji-architect'})`, `agent({agentType:'jiji-rust-implementer'})`, a hand-rolled review fan-out, `agent({agentType:'jiji-fixer'})`, `agent({agentType:'jiji-scribe'})`. Each role agent is a *leaf* — it never needs to dispatch.

This is feasible, but it **duplicates the ~260 lines of orchestration prose** from `land-subphase.md` into JS (gating, the implementer routing table, the re-review cap, halt conditions, the review fan-out). `land-subphase.md` (prose, for interactive + `claude -p`) and the workflow JS would then be **two sources of truth that drift on every change** unless manually synced + parity-tested. Avoiding this dual-maintenance tax is the core reason against a workflow loop.

## 3. The workflow orchestrator is *code, not an LLM* — best context hygiene of any driver  *(verified by tool contract + behaviour)*

The script is **plain deterministic JavaScript in a sandbox**, not an LLM. (`Date.now()`/`Math.random()` are banned precisely so resume replays identically — an LLM-interpreted script wouldn't need that.) So:

- The JS orchestrator has **no context window and cannot inflate** — its state is small JS variables.
- Each `agent()` call is a **fresh, ephemeral** LLM context: born with its prompt, returns a result, destroyed. Never shared.
- State crosses between steps as **structured data the script hands forward** (e.g. the architect's distilled `spec` object → the implementer's prompt). The architect's full reasoning never reaches the implementer — only what the script chooses to pass. This is a **context firewall**.

Multi-iteration inflation, worst → best: **interactive markdown** (main session accumulates every role's output across every iter → hits compaction) > **`loop-subphase.sh`** (fresh per iter, but one iter holds all roles in one context) > **workflow** (fresh *per role*, orchestrator accumulates nothing). The workflow genuinely wins this axis — but see §7 on why it doesn't decide the matter.

## 4. Halt → return → resume-with-args works, and replays the prefix for zero tokens  *(verified)*

A workflow that **returns normally** with a `{finalSignal:'HALT', pendingQuestion}` status can be resumed:

```
Workflow({ scriptPath, resumeFromRunId: "wf_…", args: { …sameArgs, resolution: "<answer>" } })
```

Mechanism (each identifier matters):
- A launch returns a **Task ID** (harness tracking), a **Run ID** `wf_…` (**the journal key**), and a persisted **scriptPath**.
- On resume the **whole script re-executes from the top**. For each `agent()` call the harness matches it *positionally + by `(prompt, opts)`* against that run's on-disk **journal**: identical → **replay the recorded result instantly, 0 tokens** (LLM never runs); first call whose prompt differs (now embeds the answer) or is new → **runs live, and everything after runs live**.
- You don't choose what to skip — the harness does, by journal-matching. Determinism (§3) guarantees the same call sequence up to the answer-dependent branch.

- **Probe:** run 1 `args:{answer:""}` → returned `{phase:'halted'}` (Run ID `wf_e55b05c0-16a`). Resume `resumeFromRunId` + `args:{answer:"blue"}` → `step1` replayed (token count proved 0 new tokens — `agent_count` is cumulative and counts cached agents, so trust tokens not count), `step2` ran live with "blue".
- **Authoring rule:** the cache key is per-`agent()`-call `(prompt, opts)`, NOT global `args`. Augmenting `args` is safe **only if pre-halt prompts don't embed the answer** (else their prompt changes and they re-run). Feedback can only enter where the script was *written* to read `args` and branch — injection points are a fixed, pre-baked contract.

## 5. Workflow resume is amnesiac *and* blind to manual edits — hostile to mid-loop intervention  *(verified mechanism)*

The journal stores each agent's **distilled return value**, not its conversation. So:
- A "resumed" agent is really a **fresh agent re-seeded from prompt text** — it has none of its prior turn-by-turn reasoning. Agent memory across a halt is **manual** (feed the prior result back into the prompt).
- **Replayed (cached) steps reflect run-1 state and cannot see manual changes** you make between halt and resume. If you hand-fix code mid-stream, only *new* post-branch agents see it; the replayed prefix is frozen. **Side-effecting agents that already committed do NOT re-fire on replay** (good — no double-commit), but that same freeze makes ad-hoc intervention unsound.

This is the decisive flexibility gap: a workflow is a *deterministic replay machine*; the conversational loop (`loop-subphase.sh` fresh `claude -p` per iter + a live LLM orchestrator) lets you stop, hand-fix, and have the next iteration naturally read current repo state.

## 6. Per-agent resume with full context (`SendMessage`) — off by default, real when enabled, **main-session only**  *(verified)*

- Default harness: **no `SendMessage` tool** (`ToolSearch select:SendMessage` → no match). Per-agent conversation resume is unavailable. The Agent-launch boilerplate templates in a "Use SendMessage to continue this agent" line *even when the tool isn't provisioned* — ignore it.
- With **`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`** set: `SendMessage{to:<agentId>, message, summary}` **resumes a completed/stopped background agent WITH FULL CONTEXT.**
  - **Probe:** agent told secret `KOALA-7731-VELVET` in turn 1, replied `READY`, came to rest. A `SendMessage` follow-up asking it to recall the secret returned the exact token — context the follow-up did not contain. Harness: *"was stopped (completed); resumed it in the background."*
- **Critical scope:** `SendMessage` is a **main-session tool. A workflow's `agent()` cannot call it.** So per-agent resume helps the **conversational loop** (interactive `/jiji:land-subphase` / `/jiji:loop` could resume the architect at an escalation by holding its `agentId` instead of re-dispatching a fresh one) and is **structurally unavailable to a workflow**.
- Other resume facts: Task tools are metadata-only (no agent input); forks are a session snapshot, not a live entity; the Agent SDK offers manual *session-level* resume only; `claude --resume` reattaches the whole top-level session (distilled subagent results, not a subagent's inner reasoning).

## 7. Session-binding  *(partly inferred)*

Workflow resume is **same-session only** (`resumeFromRunId`); the docs' fallback for a lost session is "hand-author a continuation script from the jsonl." Whether a background workflow survives the CC session *closing* is **not verified** (assumed to die with the session). `loop-subphase.sh` (`claude -p`, independent OS process) is the verified-detachable path. (For the current operator this is moot — session is kept open in tmux.)

---

## Decision: retire the workflow driver, adopt a conversational `/jiji:loop`

| Axis | Workflow (1b) | Conversational loop (`/jiji:loop` over `loop-subphase.sh`) |
|---|---|---|
| Nested role dispatch | ✅ (script-level only) | ✅ (fresh `claude -p` per iter) |
| Single source of truth | ❌ duplicates `land-subphase.md` into JS | ✅ prose `land-subphase.md` |
| Context hygiene over many iters | ✅ best (per-role) | ⚠️ adequate (per-iter via `claude -p`) |
| Mid-loop manual intervene-then-continue | ❌ replay is frozen/amnesiac | ✅ next iter reads current state |
| Per-agent resume of the architect | ❌ no `SendMessage` in workflows | ✅ with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |
| Orchestration in editable prose | ❌ JS literals | ✅ markdown |
| `/workflows` task tracking | ✅ | ❌ (uses bg-notify + inline summaries) |

For an operator who keeps a session open and intervenes, the workflow's wins (task tracking, marginal context-hygiene edge) do not justify forfeiting single-source-of-truth, intervene-and-continue, and the only path that can use `SendMessage` per-agent resume. **Verdict: adopt the conversational `/jiji:loop`; retire `/jiji:flow`.**
