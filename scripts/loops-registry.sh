#!/usr/bin/env bash
# loops-registry.sh — emit the merged jiji loop-target registry on stdout.
#
# THE REGISTRY IS SPLIT BY DD VISIBILITY, NOT BY SECRECY:
#
#   loops.conf                  public workspace repo — rows whose DD ships inside
#                               its own tool repo (cli, jiji-do, ff-restore*, ...)
#   specs/<owner>/loops.conf    access-restricted specs overlay — rows whose
#                               dd_path points into specs/. Absent without
#                               overlay access; naming them here would defeat
#                               the point of moving them out.
#
# Splitting this way keeps unreleased initiative names, batch cadence, and triage
# rationale out of the public repo — including the commit log, which used to
# publish every batch repoint — while the schema, the loop machinery, and every
# publicly-runnable target stay legible to anyone who clones the workspace.
#
# Output: one `name|language|code_repo|dd_path|dd_commit_repo` row per line, with
# comments and blank lines already stripped. Parse fields with `awk -F'|'`.
#
# MERGE RULE — strict union, duplicates forbidden. A target name defined in more
# than one half is a hard error (exit 3), never a silent shadow. Rationale: the
# loop drivers already STOP on an unregistered target rather than guessing, so an
# ambiguous one must fail the same way — loudly, at the same point. A row that
# silently shadowed another would route an implementer at the wrong repo.
#
# Usage:
#   scripts/loops-registry.sh              # every row, merged
#   scripts/loops-registry.sh <target>     # just that target's row (exit 1 if absent)
#
# Exit codes: 0 ok · 1 unknown target · 3 duplicate target across halves.

set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"

# Every registry half, public first. The overlay is owner-scoped by GitHub
# username (specs/<owner>/...), so glob rather than hardcode a single owner.
REGISTRY_FILES=("$WORKSPACE/loops.conf")
for f in "$WORKSPACE"/specs/*/loops.conf; do
  [ -f "$f" ] && REGISTRY_FILES+=("$f")
done

# strip_rows <file> — emit one file's data rows (no comments, no blank lines).
# A missing file emits nothing and succeeds: the specs overlay is legitimately
# absent for anyone without access, and the public rows must keep working.
strip_rows() {
  [ -f "$1" ] || return 0
  awk -F'|' '!/^#/ && NF' "$1"
}

# merged_registry <file>... — emit the union of every half's rows, in file order
# (public first), enforcing the no-duplicate-name rule above.
#
# A collision names the offending target AND the files it came from: the halves
# live in different git repos, so "duplicate: refactor" alone would send you
# looking in the wrong checkout. Returning non-zero aborts the whole script under
# `set -e` — deliberate, since every caller must treat an ambiguous registry as
# fatal rather than proceed on a partial target list.
merged_registry() {
  local rows dups name where f
  rows="$(for f in "$@"; do strip_rows "$f"; done)"
  dups="$(printf '%s\n' "$rows" | awk -F'|' 'NF {print $1}' | sort | uniq -d)"

  if [ -n "$dups" ]; then
    echo "loops-registry: target defined in more than one registry half —" >&2
    while IFS= read -r name; do
      where=""
      for f in "$@"; do
        [ -f "$f" ] || continue
        awk -F'|' -v t="$name" '!/^#/ && NF && $1==t {found=1} END {exit !found}' "$f" || continue
        where="${where:+$where, }${f#"$WORKSPACE"/}"
      done
      printf '  %s  (%s)\n' "$name" "$where" >&2
    done <<< "$dups"
    echo "Delete one of the rows before any loop can run." >&2
    return 3
  fi

  printf '%s\n' "$rows"
}

rows="$(merged_registry "${REGISTRY_FILES[@]}")"

if [ $# -eq 0 ]; then
  printf '%s\n' "$rows"
  exit 0
fi

row="$(printf '%s\n' "$rows" | awk -F'|' -v t="$1" '$1==t')"
if [ -z "$row" ]; then
  echo "loops-registry: unknown target '$1'" >&2
  echo "valid targets:" >&2
  printf '%s\n' "$rows" | awk -F'|' 'NF {print "  "$1}' >&2
  exit 1
fi
printf '%s\n' "$row"
