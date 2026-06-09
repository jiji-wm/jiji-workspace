#!/bin/bash
# Live-patch pr-review-toolkit plugin agents to set workspace-preferred model:
# values without forking or maintaining shadow agents. Runs as a SessionStart
# hook (wired in .claude/settings.json) and can also be invoked manually after
# /plugin update.
#
# Target overrides — narrowly scoped to the two low-stakes single-axis voices:
#   comment-analyzer:  inherit -> sonnet
#   pr-test-analyzer:  inherit -> sonnet
#
# code-reviewer and code-simplifier are left at upstream opus (highest-leverage
# review voices; broad reasoning benefits both). silent-failure-hunter and
# type-design-analyzer are left at inherit (resolves to workspace opus default).
#
# The script searches ~/.claude/plugins/cache/ (where auto-update puts freshly
# pulled versions) and never touches the marketplace clone (which auto-update
# git-fast-forwards and would conflict if edited).

set -u
exec 2>/dev/null

CACHE_DIR="$HOME/.claude/plugins/cache/claude-plugins-official/pr-review-toolkit"
LOG_DIR="$HOME/.cache/jiji-loop"
LOG="$LOG_DIR/pr-review-toolkit-patch.log"

# Only write to log when something actually changed — no spam on idempotent runs.
CHANGED=0

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

mkdir -p "$LOG_DIR" || exit 0

set_model() {
  local file="$1" want="$2" tmp
  [[ -f "$file" ]] || return 0

  local cur
  cur=$(awk '/^model:[[:space:]]/{sub(/^model:[[:space:]]+/,""); print; exit}' "$file")

  if [[ -z "$cur" ]]; then
    echo "$(ts) WARN no model: line in $file" >> "$LOG"
    return 0
  fi

  [[ "$cur" == "$want" ]] && return 0  # already at target — idempotent

  tmp="${file}.patch.$$"
  if sed "s|^model:[[:space:]].*|model: $want|" "$file" > "$tmp" && mv "$tmp" "$file"; then
    echo "$(ts) patched $(basename "$(dirname "$file")")/$(basename "$file"): $cur -> $want" >> "$LOG"
    CHANGED=1
  else
    rm -f "$tmp"
  fi
}

# Walk all versioned cache directories under the plugin root.
# Each desired override: agent name + target model.
for spec in "comment-analyzer=sonnet" "pr-test-analyzer=sonnet"; do
  agent="${spec%%=*}"
  model="${spec##*=}"
  for f in "$CACHE_DIR"/*/agents/"$agent".md \
           "$CACHE_DIR"/"$agent".md; do
    set_model "$f" "$model"
  done
done

[[ $CHANGED -eq 1 ]] && echo "$(ts) pr-review-toolkit patch complete" >> "$LOG"
exit 0
