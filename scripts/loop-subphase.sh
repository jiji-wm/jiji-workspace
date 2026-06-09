#!/usr/bin/env bash
# loop-subphase.sh — autonomous sub-phase orchestrator for any jiji loop target.
#
# Wraps `claude -p "/jiji:land-subphase <target> --autonomous"` in a fresh-context
# loop: each iteration is a separate Claude Code session (no growing context, no
# compaction degradation), iterates until the agent emits LOOP_HALT / LOOP_ERROR
# or MAX_ITER is reached. The agent owns sub-phase logic; this script owns
# iteration cadence and halt-on-signal.
#
# Usage:
#   scripts/loop-subphase.sh <target> [MAX_ITER]   # default MAX_ITER=4
#   <target> must be a name registered in loops.conf (e.g. compositor, cli).
#
# Resume after a halt: `claude --resume <session-id>` (printed on halt).
# Cancel: Ctrl-C between iterations, or kill the running `claude` process.

set -euo pipefail

LOOP="${1:-}"
MAX_ITER="${2:-4}"

# Run from the workspace root so /jiji:* commands and loops.conf resolve.
WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSPACE"

# Validate the target against the loops.conf registry; any registered target is
# drivable autonomously with no script change.
if [ -z "$LOOP" ] || ! awk -F'|' '!/^#/ && NF {print $1}' loops.conf | grep -qx "$LOOP"; then
  echo "usage: $(basename "$0") <target> [MAX_ITER]" >&2
  echo "valid targets:" >&2
  awk -F'|' '!/^#/ && NF {print "  "$1}' loops.conf >&2
  exit 2
fi
CMD="/jiji:land-subphase $LOOP --autonomous"

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/jiji-loop"
mkdir -p "$LOG_DIR"
RUN_LOG="$LOG_DIR/${LOOP}-$(date +%Y%m%d-%H%M%S).log"

# Per-iteration the agent writes a live JSONL transcript here. The session ID
# isn't known until claude finishes (with --output-format json), but the file
# itself appears immediately when the session starts — so a background watcher
# can detect it and echo `tail -f <path>` for the user to run in another shell.
SLUG="-$(printf '%s' "$WORKSPACE" | sed 's|/|-|g; s|^-||')"
TRANSCRIPTS_DIR="$HOME/.claude/projects/$SLUG"

notify() {
  # Best-effort desktop notification; silently skip if notify-send is missing.
  command -v notify-send >/dev/null 2>&1 && notify-send "$@" || true
}

log() {
  printf '%s\n' "$*" | tee -a "$RUN_LOG"
}

log "Loop:         $LOOP"
log "Command:      $CMD"
log "Max iter:     $MAX_ITER"
log "Workspace:    $WORKSPACE"
log "Run log:      $RUN_LOG"
log "Transcripts:  $TRANSCRIPTS_DIR"
log "  (Agent's live JSONL appears here; iteration banner echoes the exact tail command.)"
log "Started:      $(date)"

for i in $(seq 1 "$MAX_ITER"); do
  log ""
  log "=== Iteration $i / $MAX_ITER — $(date +%H:%M:%S) ==="

  ITER_OUT="$LOG_DIR/${LOOP}-iter${i}-$(date +%H%M%S).json"

  # Snapshot existing transcripts so the watcher can spot the new one.
  PRE_SNAPSHOT="$(mktemp -t jiji-loop-snap.XXXXXX)"
  ls "$TRANSCRIPTS_DIR"/*.jsonl 2>/dev/null | sort > "$PRE_SNAPSHOT" || true

  # Background watcher: detects this iteration's new JSONL and echoes
  # the live tail command for the user. Times out at ~15s so we don't
  # leak watchers if the session never starts.
  (
    for _ in $(seq 1 15); do
      sleep 1
      NEW="$(comm -13 "$PRE_SNAPSHOT" <(ls "$TRANSCRIPTS_DIR"/*.jsonl 2>/dev/null | sort) | head -1)"
      if [ -n "$NEW" ]; then
        SID="$(basename "$NEW" .jsonl)"
        {
          printf '  📺 Live transcript (raw):       tail -f %q\n' "$NEW"
          printf '     Or human-readable filter:    %s/scripts/loop-tail.sh %s\n' "$WORKSPACE" "$SID"
        } | tee -a "$RUN_LOG"
        break
      fi
    done
    rm -f "$PRE_SNAPSHOT"
  ) &
  WATCHER_PID=$!

  if ! claude -p "$CMD" \
              --output-format json \
              --permission-mode auto \
              > "$ITER_OUT" 2>>"$RUN_LOG"; then
    kill "$WATCHER_PID" 2>/dev/null || true
    rm -f "$PRE_SNAPSHOT"
    log "  ✗ claude exited non-zero (see $RUN_LOG and $ITER_OUT)"
    notify -u critical "Jiji $LOOP loop: claude error" "Iteration $i — see $RUN_LOG"
    exit 1
  fi

  # Watcher should have exited on its own once the file appeared; reap if not.
  kill "$WATCHER_PID" 2>/dev/null || true
  wait "$WATCHER_PID" 2>/dev/null || true
  rm -f "$PRE_SNAPSHOT"

  final="$(jq -r '.result // empty' < "$ITER_OUT")"
  session="$(jq -r '.session_id // empty' < "$ITER_OUT")"
  signal="$(printf '%s\n' "$final" | grep -oE '^LOOP_(CONTINUE|HALT|ERROR)(:[^[:space:]]*)?' | tail -1 || true)"

  log "  Session:    $session"
  [ -n "$session" ] && log "  Transcript: $TRANSCRIPTS_DIR/${session}.jsonl"
  log "  Signal:     ${signal:-<none>}"

  case "${signal%%:*}" in
    LOOP_CONTINUE)
      log "  ✓ Sub-phase landed; continuing."
      ;;
    LOOP_HALT)
      reason="${signal#LOOP_HALT:}"
      log "  ⏸  Halted: $reason"
      log "  Resume: claude --resume $session"
      notify "Jiji $LOOP loop paused" \
        "Iter $i — $reason"$'\n'"Resume: claude --resume $session"
      exit 0
      ;;
    LOOP_ERROR)
      reason="${signal#LOOP_ERROR:}"
      log "  ✗ Error: $reason"
      log "  Resume: claude --resume $session"
      notify -u critical "Jiji $LOOP loop errored" \
        "Iter $i — $reason"$'\n'"Resume: claude --resume $session"
      exit 1
      ;;
    *)
      log "  ✗ Missing or malformed LOOP_* signal — agent likely misbehaved"
      log "  Last 20 lines of agent output:"
      printf '%s\n' "$final" | tail -20 | sed 's/^/    /' | tee -a "$RUN_LOG"
      log "  Resume: claude --resume $session"
      notify -u critical "Jiji $LOOP loop: missing signal" \
        "Iter $i — see $RUN_LOG"
      exit 1
      ;;
  esac
done

log ""
log "=== Reached MAX_ITER=$MAX_ITER; stopping for fresh-context discipline. ==="
log "Re-run to continue: $0 $LOOP $MAX_ITER"
notify "Jiji $LOOP loop: $MAX_ITER iterations completed" \
  "Stopped at iteration cap. Re-run script to continue."
