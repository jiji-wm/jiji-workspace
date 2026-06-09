#!/bin/bash
# PostCompact hook — append a timestamped TSV row to ~/.cache/jiji-loop/compactions.log
# for after-the-fact grepping ("did the loop compact during a long run?").
# Wired in settings.json with matcher: "auto" so manual /compact invocations
# don't generate spurious entries.
#
# Defensive: any internal failure exits 0 with no output. Never blocks the loop.

set -u
exec 2>/dev/null

LOG_DIR="$HOME/.cache/jiji-loop"
mkdir -p "$LOG_DIR" || exit 0
log="$LOG_DIR/compactions.log"

command -v jq >/dev/null || exit 0

payload=$(cat) || exit 0

matcher=$(printf '%s' "$payload" | jq -r '.matcher // .compact_matcher // "unknown"')
session=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"')
summary_len=$(printf '%s' "$payload" | jq -r '(.summary // "") | length')

printf '%s\tmatcher=%s\tsession=%s\tcwd=%s\tsummary_len=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$matcher" "$session" "$PWD" "$summary_len" >> "$log"
