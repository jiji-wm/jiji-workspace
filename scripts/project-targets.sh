# Shared target registry for build.sh / install.sh. Sourced, not executed.
# Requires $WORKSPACE (workspace root) to be set by the caller.
#
# Two install regimes:
#   compositor (upstream, jiji) — system-wide via sudo: binary + session files
#   tool (everything else)      — per-user cargo install into ~/.cargo/bin

TARGETS="upstream jiji jiji-activities jiji-do jiji-firefox-workspaces jiji-hamster-bridge"

target_dir() {
    case "$1" in
        upstream)                echo "$WORKSPACE/repos/upstream/niri" ;;
        jiji)                    echo "$WORKSPACE/repos/jiji" ;;
        jiji-activities)         echo "$WORKSPACE/repos/jiji-activities" ;;
        jiji-do)                 echo "$WORKSPACE/repos/jiji-do" ;;
        jiji-firefox-workspaces) echo "$WORKSPACE/repos/jiji-firefox-workspaces" ;;
        jiji-hamster-bridge)     echo "$WORKSPACE/repos/jiji-hamster-bridge" ;;
        *) return 1 ;;
    esac
}

target_is_compositor() {
    case "$1" in
        upstream|jiji) return 0 ;;
        *) return 1 ;;
    esac
}

# Built binary name for tool targets. Compositor targets are detected at
# install time instead (jiji post-rename, niri otherwise).
target_bin() {
    case "$1" in
        jiji-activities)         echo "jiji-activities" ;;
        jiji-do)                 echo "jiji-do" ;;
        jiji-firefox-workspaces) echo "jiji-firefox-workspaces-host" ;;
        jiji-hamster-bridge)     echo "jiji-hamster-bridge" ;;
        *) return 1 ;;
    esac
}

# One target per line — consumed by the fish completions via `--targets`.
print_targets() {
    for t in $TARGETS; do echo "$t"; done
}

usage_targets() {
    echo "Usage: $1 [--targets] [target]" >&2
    echo "Targets:" >&2
    print_targets | sed 's/^/  /' >&2
}
