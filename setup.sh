#!/usr/bin/env bash
set -euo pipefail

# setup.sh — one-shot workspace bootstrap. Chains the individual installers in
# the right order so a fresh clone is ready with a single command:
#   1. tools/workspace-install/install.sh   `workspace` CLI on PATH + fish helpers
#   2. tools/cdr/install.sh                 cdr/cdw fuzzy-cd fish helpers
#   3. scripts/clone.sh                     clone every nested repo (forks,
#                                           mirrors, hooks, specs overlay)
#   4. tools/claude-plugins/install.sh      Claude Code plugins (opt-in)
#
# Steps 1-3 run by default. Step 4 mutates ~/.claude, so it's opt-in:
# --plugins (or --all). Each step is idempotent — re-running setup.sh is safe.
#
# Usage:
#   ./setup.sh                  # tools + repos
#   ./setup.sh --plugins        # + Claude Code plugins
#   ./setup.sh --all            # everything
#   ./setup.sh --dry-run        # preview, change nothing (combine with the above)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=0
WITH_PLUGINS=0
for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY_RUN=1 ;;
        --plugins)  WITH_PLUGINS=1 ;;
        --all)      WITH_PLUGINS=1 ;;
        --help|-h)  awk 'NR>3 && /^#/{sub(/^# ?/,"");print;next} NR>3{exit}' "$0"; exit 0 ;;
        *) echo "setup: unknown flag '$arg'" >&2; exit 2 ;;
    esac
done

step() { printf '\n== %s ==\n' "$*"; }

# run_step <supports-dry-run 0|1> <command...>
run_step() {
    local supports_dry="$1"; shift
    if (( DRY_RUN )); then
        if (( supports_dry )); then
            "$@" --dry-run
        else
            printf '[dry-run] would run: %s\n' "$*"
        fi
    else
        "$@"
    fi
}

total=3; (( WITH_PLUGINS )) && total=$((total+1))
n=0
nstep() { n=$((n+1)); step "$n/$total  $*"; }

nstep "workspace CLI + fish helpers"
run_step 0 "$ROOT/tools/workspace-install/install.sh"

nstep "cdr/cdw fuzzy-cd helpers"
run_step 0 "$ROOT/tools/cdr/install.sh"

nstep "clone nested repos (repos.conf + fork bootstrap + git hooks)"
run_step 0 "$ROOT/scripts/clone.sh"

if (( WITH_PLUGINS )); then
    nstep "Claude Code plugins"
    run_step 1 "$ROOT/tools/claude-plugins/install.sh"
else
    printf '\nnote: skipped Claude plugin install. Run with --plugins (or --all) to add them.\n'
fi

printf '\nsetup: done%s.\n' "$( (( DRY_RUN )) && printf ' (dry-run)' )"
