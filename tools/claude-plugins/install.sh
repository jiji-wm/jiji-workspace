#!/usr/bin/env bash
set -euo pipefail

# install.sh — provision the Claude Code plugins this workspace relies on.
#
# All plugins come from one marketplace (anthropics/claude-plugins-official)
# and install at user scope, so they're available in every workspace on the
# machine. The manifest below is the curated "actively used" set: the loop
# system's review toolkit, the superpowers process skills, and one LSP per
# workspace language (Rust everywhere, Python for jiji-hamster).
#
# Idempotent: adds the marketplace only if missing, installs only plugins not
# already present, and re-running is a no-op. Individual install failures are
# reported at the end but don't abort the rest of the run.
#
# Usage:
#   ./install.sh              # add marketplace + install missing plugins
#   ./install.sh --dry-run    # show what would happen, change nothing
#   ./install.sh --scope=project   # install at project scope instead of user
#   ./install.sh --list       # print the manifest and exit

MARKETPLACE_NAME="claude-plugins-official"
MARKETPLACE_SOURCE="anthropics/claude-plugins-official"

# Edit this list to change what the workspace provisions. Grouped only for
# readability — install order is irrelevant.
PLUGINS=(
    # skill / agent plugins the loop system and docs reference
    superpowers          # brainstorming/TDD/debugging process skills
    pr-review-toolkit    # /pr-review-toolkit:review-pr — the loop's review stage
    # language servers (one per workspace language)
    rust-analyzer-lsp    # Rust: compositor + all CLI tools
    pyright-lsp          # Python: jiji-hamster (waf/GTK)
)

DRY_RUN=0
SCOPE="user"
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --scope)   echo "claude-plugins: --scope needs a value, use --scope=VALUE" >&2; exit 2 ;;
        --scope=*) SCOPE="${arg#--scope=}" ;;
        --list)
            printf 'Marketplace: %s (%s)\n\nPlugins:\n' "$MARKETPLACE_NAME" "$MARKETPLACE_SOURCE"
            for p in "${PLUGINS[@]}"; do printf '  %s\n' "$p"; done
            exit 0
            ;;
        --help|-h)
            awk 'NR>3 && /^#/{sub(/^# ?/,"");print;next} NR>3{exit}' "$0"
            exit 0
            ;;
        *) echo "claude-plugins: unknown flag '$arg'" >&2; exit 2 ;;
    esac
done

if ! command -v claude >/dev/null 2>&1; then
    echo "claude-plugins: the 'claude' CLI is not on \$PATH — install Claude Code first." >&2
    exit 1
fi

run() {
    if (( DRY_RUN )); then
        printf '[dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

# --- marketplace ---------------------------------------------------------
if claude plugin marketplace list 2>/dev/null | grep -qw "$MARKETPLACE_NAME"; then
    printf '  %-24s marketplace already configured\n' "$MARKETPLACE_NAME"
else
    printf '── adding marketplace %s ──\n' "$MARKETPLACE_NAME"
    run claude plugin marketplace add "$MARKETPLACE_SOURCE"
fi

# --- plugins -------------------------------------------------------------
installed="$(claude plugin list 2>/dev/null || true)"
FAILED=()
INSTALLED_NOW=()

for plugin in "${PLUGINS[@]}"; do
    if printf '%s\n' "$installed" | grep -qF "$plugin@$MARKETPLACE_NAME"; then
        printf '  %-24s already installed\n' "$plugin"
        continue
    fi
    printf '── installing %s ──\n' "$plugin"
    if run claude plugin install "$plugin@$MARKETPLACE_NAME" --scope "$SCOPE"; then
        INSTALLED_NOW+=("$plugin")
    else
        printf 'warn: install failed for %s\n' "$plugin" >&2
        FAILED+=("$plugin")
    fi
done

if (( DRY_RUN )); then
    exit 0
fi

printf '\nclaude-plugins: done.'
(( ${#INSTALLED_NOW[@]} )) && printf ' Newly installed: %s.' "${INSTALLED_NOW[*]}"
printf '\nRestart Claude Code (or run /plugin) to pick up newly installed plugins.\n'

if (( ${#FAILED[@]} > 0 )); then
    printf '\nclaude-plugins: %d plugin(s) failed:\n' "${#FAILED[@]}" >&2
    for f in "${FAILED[@]}"; do printf '  %s\n' "$f" >&2; done
    exit 1
fi
