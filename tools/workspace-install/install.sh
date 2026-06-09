#!/usr/bin/env bash
# install.sh — install the jiji workspace manager into the user's environment:
#   1. PATH symlinks: ~/.local/bin/workspace and ~/.local/bin/ws
#      (via the CWD-detecting dispatcher workspace-dispatch.sh)
#   2. Fish files under fish/{functions,completions,conf.d}/ symlinked into
#      ~/.config/fish/{functions,completions,conf.d}/
#
# Both are symlinks back into the workspace; git pull lights up changes
# without re-running the installer.
#
# Usage:
#   ./install.sh                  # install everything
#   ./install.sh --bin-only       # PATH symlinks only
#   ./install.sh --completion-only # fish files only
#   ./install.sh --uninstall      # remove everything
#   ./install.sh --status         # report state
#   ./install.sh --bin-dir DIR    # override PATH symlink target dir
#   ./install.sh -h | --help      # show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

WORKSPACE_BIN="$WORKSPACE_ROOT/workspace"
DISPATCH_SRC="$SCRIPT_DIR/workspace-dispatch.sh"
FISH_TREE="$SCRIPT_DIR/fish"

BIN_DIR="$HOME/.local/bin"
FISH_BASE="${XDG_CONFIG_HOME:-$HOME/.config}/fish"

INSTALL_BIN=1
INSTALL_FISH=1
ACTION="install"

if [[ -t 1 ]]; then
    GRN=$'\033[32m' YLW=$'\033[33m' RED=$'\033[31m' DIM=$'\033[2m' RST=$'\033[0m'
else
    GRN='' YLW='' RED='' DIM='' RST=''
fi

usage() { sed -n '2,/^$/{ s/^# \?//; p }' "$0"; }
die()   { printf '%serror:%s %s\n' "$RED" "$RST" "$*" >&2; exit 1; }
info()  { printf '%s::%s %s\n' "$GRN" "$RST" "$*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bin-only)        INSTALL_FISH=0; shift ;;
        --completion-only) INSTALL_BIN=0; shift ;;
        --bin-dir)         BIN_DIR="$2"; shift 2 ;;
        --uninstall)       ACTION="uninstall"; shift ;;
        --status)          ACTION="status"; shift ;;
        -h|--help)         usage; exit 0 ;;
        *)                 die "unknown argument: $1 (try --help)" ;;
    esac
done

[[ -f "$WORKSPACE_BIN" ]] || die "missing workspace script: $WORKSPACE_BIN"
[[ -x "$DISPATCH_SRC"  ]] || die "missing or non-executable dispatcher: $DISPATCH_SRC"
[[ -d "$FISH_TREE"     ]] || die "missing fish tree: $FISH_TREE"

BIN_DEST="$BIN_DIR/workspace"
WS_BIN_DEST="$BIN_DIR/ws"

install_symlink() {
    local src="$1" dest="$2" label="$3"
    if [[ -e "$dest" && ! -L "$dest" ]]; then
        printf '  %s%s:%s %snot a symlink — move it aside first%s\n' \
            "$YLW" "$label" "$RST" "$DIM" "$RST"
        return
    fi
    mkdir -p "$(dirname "$dest")"
    ln -sf "$src" "$dest"
    printf '  %s%s:%s %s -> %s\n' "$GRN" "$label" "$RST" "$dest" "$src"
}

remove_symlink() {
    local dest="$1" label="$2"
    if [[ -L "$dest" ]]; then
        rm "$dest"
        printf '  %sremoved%s %s\n' "$YLW" "$RST" "$dest"
    fi
}

report_status() {
    local dest="$1" label="$2"
    if [[ -L "$dest" ]]; then
        printf '  %s%-35s%s -> %s\n' "$GRN" "$label" "$RST" "$(readlink "$dest")"
    else
        printf '  %s%-35s%s not installed\n' "$YLW" "$label" "$RST"
    fi
}

check_path() {
    case ":$PATH:" in
        *":$BIN_DIR:"*) return 0 ;;
        *) printf '  %snote:%s %s is not in $PATH\n' "$YLW" "$RST" "$BIN_DIR" ;;
    esac
}

walk_fish_tree() {
    local action="$1" kind file dest
    for kind in functions completions conf.d; do
        [[ -d "$FISH_TREE/$kind" ]] || continue
        for file in "$FISH_TREE/$kind"/*.fish; do
            [[ -f "$file" ]] || continue
            dest="$FISH_BASE/$kind/$(basename "$file")"
            case "$action" in
                install) install_symlink "$file" "$dest" "fish $kind/$(basename "$file")" ;;
                remove)  remove_symlink              "$dest" "fish $kind/$(basename "$file")" ;;
                report)  report_status               "$dest" "fish $kind/$(basename "$file")" ;;
            esac
        done
    done
}

case "$ACTION" in
    install)
        info "Installing jiji workspace tools"
        if [[ "$INSTALL_BIN" -eq 1 ]]; then
            install_symlink "$DISPATCH_SRC" "$BIN_DEST"    "PATH symlink (workspace)"
            install_symlink "$DISPATCH_SRC" "$WS_BIN_DEST" "PATH symlink (ws alias)"
            check_path || true
        fi
        if [[ "$INSTALL_FISH" -eq 1 ]]; then
            walk_fish_tree install
        fi
        info "Done. Run 'workspace help' to verify."
        ;;
    uninstall)
        info "Uninstalling jiji workspace tools"
        if [[ "$INSTALL_BIN" -eq 1 ]]; then
            remove_symlink "$BIN_DEST"    "PATH symlink"
            remove_symlink "$WS_BIN_DEST" "PATH symlink (ws alias)"
        fi
        [[ "$INSTALL_FISH" -eq 1 ]] && walk_fish_tree remove
        ;;
    status)
        report_status "$BIN_DEST"    "PATH symlink (workspace)"
        report_status "$WS_BIN_DEST" "PATH symlink (ws alias)"
        walk_fish_tree report
        check_path || true
        ;;
esac
