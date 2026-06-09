#!/usr/bin/env bash
# loop-tail.sh — human-friendly live tail of a Claude Code session transcript.
#
# The raw JSONL transcript at ~/.claude/projects/<slug>/<session-id>.jsonl is
# one fat JSON object per line (UUIDs, request IDs, token usage, cache stats,
# the whole tool-call wire format). This wraps `tail -F` with a jq filter that
# emits one short, color-coded, timestamped line per event.
#
# Usage:
#   scripts/loop-tail.sh                       # tail newest session in this workspace
#   scripts/loop-tail.sh <session-id>          # tail specific session by ID
#   scripts/loop-tail.sh <path-to-jsonl>       # tail a specific file
#   scripts/loop-tail.sh -l                    # list available sessions (newest first)
#   scripts/loop-tail.sh -n 100                # show last 100 lines before tailing
#   scripts/loop-tail.sh -h                    # this help
#
# Output format:
#     HH:MM:SS  <main|sub>  KIND  content
#
# KIND is one of:
#   USER  — user/system message into the agent (incl. autonomous-loop sentinel)
#   ASST  — assistant prose
#   TOOL  — tool invocation (name + truncated input)
#   RES   — tool result (truncated)
#   SYS   — system event (e.g. scheduled wakeup, compact)

set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
SLUG="-$(printf '%s' "$WORKSPACE" | sed 's|/|-|g; s|^-||')"
TRANSCRIPTS_DIR="$HOME/.claude/projects/$SLUG"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's|^# \?||'
  exit "${1:-0}"
}

LINES=0
LIST=0
while getopts "n:lh" opt; do
  case "$opt" in
    n) LINES="$OPTARG" ;;
    l) LIST=1 ;;
    h) usage 0 ;;
    *) usage 2 ;;
  esac
done
shift $((OPTIND-1))

if [ "$LIST" -eq 1 ]; then
  echo "Sessions in $TRANSCRIPTS_DIR (newest first):"
  ls -lt "$TRANSCRIPTS_DIR"/*.jsonl 2>/dev/null \
    | awk '{ printf "  %s  %s  %s\n", $6, $7, $9 }' \
    | head -20
  exit 0
fi

target="${1:-}"
if [ -z "$target" ]; then
  FILE="$(ls -t "$TRANSCRIPTS_DIR"/*.jsonl 2>/dev/null | head -1 || true)"
elif [ -f "$target" ]; then
  FILE="$target"
elif [ -f "$TRANSCRIPTS_DIR/$target.jsonl" ]; then
  FILE="$TRANSCRIPTS_DIR/$target.jsonl"
elif [ -f "$TRANSCRIPTS_DIR/$target" ]; then
  FILE="$TRANSCRIPTS_DIR/$target"
else
  echo "No transcript found: $target" >&2
  echo "Looked in: $TRANSCRIPTS_DIR" >&2
  echo "Try '$0 -l' to list available sessions." >&2
  exit 1
fi
[ -n "${FILE:-}" ] || {
  echo "No transcripts in $TRANSCRIPTS_DIR" >&2
  exit 1
}

echo "Tailing: $FILE" >&2
echo "        (Ctrl-C to stop)" >&2
echo "" >&2

# Colors (only when stdout is a TTY — degrade gracefully to plain text on pipes).
if [ -t 1 ]; then
  C_TS=$'\033[2;37m'    # dim grey
  C_USER=$'\033[1;36m'  # bold cyan
  C_ASST=$'\033[1;32m'  # bold green
  C_TOOL=$'\033[1;33m'  # bold yellow
  C_RES=$'\033[33m'     # yellow
  C_SYS=$'\033[2;34m'   # dim blue
  C_SUB=$'\033[35m'     # magenta (sub-agent marker)
  C_OFF=$'\033[0m'
else
  C_TS= C_USER= C_ASST= C_TOOL= C_RES= C_SYS= C_SUB= C_OFF=
fi

# jq filter: one human-readable line per JSONL event.
#   Output shape: "HH:MM:SS|<sub|   >|KIND|content"
#   Metadata events (attachment, custom-title, file-history-snapshot) are dropped.
read -r -d '' FILTER <<'JQ' || true
  def cut(n): if (. | length) > n then .[0:n] + "…" else . end;
  def flat: tostring | gsub("\n"; " ⏎ ");
  def hms: (.timestamp // "") | split("T")[1]? // "" | split(".")[0];
  def src: if (.isSidechain // false) then "sub" else "   " end;

  # Drop transcript-internal records that have no interactional content.
  select(.type | IN("attachment", "custom-title", "file-history-snapshot") | not) |
  # Require a real timestamp; transcript-meta records without one would
  # otherwise render as "null" lines.
  select(.timestamp != null) |

  hms as $t |
  src as $s |
  if .type == "assistant" then
    (.message.content // []) | (if type=="array" then .[] else . end) | (
      if .type == "text" then
        "\($t)|\($s)|ASST|\(.text | flat | cut(800))"
      elif .type == "thinking" then
        "\($t)|\($s)|ASST|💭 \(.thinking | flat | cut(300))"
      elif .type == "tool_use" then
        "\($t)|\($s)|TOOL|\(.name) \(.input | flat | cut(300))"
      else
        "\($t)|\($s)|ASST|(\(.type))"
      end
    )
  elif .type == "user" then
    if (.message.content | type) == "string" then
      "\($t)|\($s)|USER|\(.message.content | flat | cut(500))"
    else
      (.message.content // []) | (if type=="array" then .[] else . end) | (
        if .type == "text" then
          "\($t)|\($s)|USER|\(.text | flat | cut(500))"
        elif .type == "tool_result" then
          ((.content | if type=="array" then
              map(if .text? then .text else (. | tostring) end) | join(" ")
            else (. | tostring) end) | gsub("\n"; " ⏎ ") | cut(500)) as $c |
          "\($t)|\($s)|RES |\($c)"
        else
          "\($t)|\($s)|USER|(\(.type))"
        end
      )
    end
  elif .type == "system" then
    "\($t)|\($s)|SYS |\(.subtype // "?"): \(.content // "" | flat | cut(200))"
  else
    "\($t)|\($s)|?   |\(.type)"
  end
JQ

# Recolor the pipe-delimited stream. Stays readable when piped to a file or grep.
colorize() {
  awk -F '|' -v TS="$C_TS" -v USER="$C_USER" -v ASST="$C_ASST" -v TOOL="$C_TOOL" \
      -v RES="$C_RES" -v SYS="$C_SYS" -v SUB="$C_SUB" -v OFF="$C_OFF" '
    {
      time = $1; sub_marker = $2; kind = $3;
      # rest = everything after the third pipe
      rest = $0; for (i=1;i<=3;i++) sub("[^|]*\\|", "", rest);
      if (kind == "USER") c = USER;
      else if (kind == "ASST") c = ASST;
      else if (kind == "TOOL") c = TOOL;
      else if (kind == "RES ") c = RES;
      else if (kind == "SYS ") c = SYS;
      else c = "";
      sub_col = (sub_marker == "sub") ? SUB : "";
      printf "%s%s%s  %s%s%s  %s%s%s  %s\n", \
        TS, time, OFF, sub_col, sub_marker, OFF, c, kind, OFF, rest;
      fflush();
    }
  '
}

# `--unbuffered` requires jq ≥ 1.6; degrade silently if absent.
JQ_FLAGS="-Rr"
jq --help 2>&1 | grep -q -- '--unbuffered' && JQ_FLAGS="--unbuffered $JQ_FLAGS"

# shellcheck disable=SC2086
tail -n "$LINES" -F "$FILE" 2>/dev/null \
  | jq $JQ_FLAGS 'fromjson? // empty | '"$FILTER" \
  | colorize
