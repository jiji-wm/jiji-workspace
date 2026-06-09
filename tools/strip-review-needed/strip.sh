#!/usr/bin/env bash
# Strip Review-Needed: trailers from a range of commits in the current sub-repo.
#
# Default range: @{upstream}..HEAD (unpushed only).
# Refuses pushed commits without --force; refuses dirty worktree.
# Does not push.
set -euo pipefail

APPLY=0
FORCE=0
RANGE=""

usage() {
  cat <<'EOF'
Usage: strip-review-needed [--apply] [--force] [<range>]

  <range>     Defaults to @{upstream}..HEAD (or main..HEAD / master..HEAD).
  --apply     Actually rewrite (default is preview).
  --force     Allow rewriting commits already pushed to upstream.
              Caller is responsible for the subsequent --force-with-lease push.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
    *)  RANGE="$1"; shift ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "error: not in a git repo" >&2; exit 2; }

branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
if [[ -z "$branch" ]]; then
  echo "error: HEAD is detached — checkout a branch first" >&2
  exit 2
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: dirty worktree — stash or commit first" >&2
  exit 2
fi

upstream=""
if upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null); then
  :
else
  upstream=""
fi

if [[ -z "$RANGE" ]]; then
  if [[ -n "$upstream" ]]; then
    RANGE="${upstream}..HEAD"
  elif git rev-parse --verify main >/dev/null 2>&1; then
    RANGE="main..HEAD"
  elif git rev-parse --verify master >/dev/null 2>&1; then
    RANGE="master..HEAD"
  else
    echo "error: no upstream and no main/master — pass an explicit range" >&2
    exit 2
  fi
fi

if ! git rev-list "$RANGE" >/dev/null 2>&1; then
  echo "error: invalid range: $RANGE" >&2
  exit 2
fi

mapfile -t affected < <(git log --format='%H' --grep='^Review-Needed:' "$RANGE")

if [[ ${#affected[@]} -eq 0 ]]; then
  echo "no commits with Review-Needed: in $RANGE — nothing to do"
  exit 0
fi

pushed=()
if [[ -n "$upstream" ]]; then
  upstream_sha=$(git rev-parse "$upstream")
  for sha in "${affected[@]}"; do
    if git merge-base --is-ancestor "$sha" "$upstream_sha" 2>/dev/null; then
      pushed+=("$sha")
    fi
  done
fi

echo "Branch: $branch"
echo "Range:  $RANGE"
echo "Will strip Review-Needed: from ${#affected[@]} commit(s):"
for sha in "${affected[@]}"; do
  git --no-pager log -1 --format='  %h %s' "$sha"
done
echo

if [[ ${#pushed[@]} -gt 0 ]]; then
  echo "WARNING: ${#pushed[@]} of these commit(s) are already pushed to $upstream:"
  for sha in "${pushed[@]}"; do
    git --no-pager log -1 --format='  %h %s' "$sha"
  done
  echo
  if [[ $FORCE -eq 0 ]]; then
    echo "error: refusing to rewrite pushed history without --force" >&2
    echo "       (after rewrite you would need: git push --force-with-lease)" >&2
    exit 2
  fi
  echo "(--force given — rewriting anyway; you must push --force-with-lease yourself)"
fi

if [[ $APPLY -eq 0 ]]; then
  echo "(preview — rerun with --apply to rewrite)"
  exit 0
fi

FILTER_BRANCH_SQUELCH_WARNING=1 \
  git filter-branch -f --msg-filter 'sed "/^Review-Needed:/d"' "$RANGE" >/dev/null

git update-ref -d "refs/original/refs/heads/$branch" 2>/dev/null || true

echo "stripped Review-Needed: from ${#affected[@]} commit(s)"
if [[ ${#pushed[@]} -gt 0 ]]; then
  echo "next: git push --force-with-lease"
fi
