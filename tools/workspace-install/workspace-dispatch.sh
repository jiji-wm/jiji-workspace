#!/usr/bin/env bash
# workspace-dispatch.sh — route `workspace <args>` to the workspace manager
# of the current tree.
#
# Resolution order:
#   1. $WORKSPACE_DIR (explicit override; errors if invalid).
#   2. Walk up from $PWD looking for repos.conf alongside an executable
#      workspace (or workspace.sh).
#   3. Self-locating fallback: the workspace tree containing this dispatcher
#      copy. With ~/.local/bin/workspace symlinked here, the fallback target
#      is "whichever workspace's installer ran last".
#   4. Error out.

set -euo pipefail

if [[ -t 2 ]]; then
    DIM=$'\033[2m' RST=$'\033[0m' RED=$'\033[31m'
else
    DIM='' RST='' RED=''
fi

die() {
    printf '%serror:%s %s\n' "$RED" "$RST" "$1" >&2
    shift
    for line in "$@"; do printf '       %s\n' "$line" >&2; done
    exit 1
}

try_root() {
    local dir="$1"; shift
    [[ -f "$dir/repos.conf" ]] || return 1
    for candidate in "$dir/workspace" "$dir/workspace.sh"; do
        if [[ -x "$candidate" ]]; then
            exec "$candidate" "$@"
        fi
    done
    return 1
}

# 1. Explicit override.
if [[ -n "${WORKSPACE_DIR:-}" ]]; then
    try_root "$WORKSPACE_DIR" "$@" || die \
        "WORKSPACE_DIR=$WORKSPACE_DIR is not a usable workspace" \
        "Expected repos.conf and an executable workspace (or workspace.sh) there."
fi

# 1.5. Intercept cwd-changing subcommands.
if [[ $# -ge 1 ]]; then
    case "$1" in
        cdr|cdrepo|root)
            SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
            die "'workspace $1' changes the calling shell's working directory and must run in-shell (fish only)." \
                "Install the fish wrappers via:" \
                "  $SELF_DIR/install.sh" \
                "Or use the standalone 'cdr' / 'cdr-jiji' / 'cdw' fish functions."
            ;;
    esac
fi

# 2. CWD walk-up.
dir="$PWD"
while [[ "$dir" != "/" ]]; do
    try_root "$dir" "$@" || true
    dir="$(dirname "$dir")"
done

# 3. Self-locating fallback.
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SELF_WORKSPACE="$(cd "$(dirname "$SELF")/../.." 2>/dev/null && pwd)" || SELF_WORKSPACE=""

if [[ -n "$SELF_WORKSPACE" && -f "$SELF_WORKSPACE/repos.conf" ]]; then
    for candidate in "$SELF_WORKSPACE/workspace" "$SELF_WORKSPACE/workspace.sh"; do
        if [[ -x "$candidate" ]]; then
            [[ -t 2 ]] && printf '%sworkspace:%s cwd outside any tree, using default %s\n' \
                "$DIM" "$RST" "$SELF_WORKSPACE" >&2
            exec "$candidate" "$@"
        fi
    done
fi

# 4. Nothing worked.
die "no workspace found above $PWD" \
    "Looked up the tree for repos.conf with an executable workspace" \
    "(or workspace.sh). cd into a workspace, set" \
    "WORKSPACE_DIR=/path/to/workspace, or re-run install.sh from a" \
    "valid workspace tree."
