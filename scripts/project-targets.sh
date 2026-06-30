# Shared target registry for build.sh / install.sh. Sourced, not executed.
# Requires $WORKSPACE (workspace root) to be set by the caller.
#
# Three install regimes (see target_regime):
#   compositor (upstream, jiji)        — cargo build; system-wide via sudo: binary + session files
#   cargo      (Rust tools)            — cargo install --offline into ~/.cargo/bin (per-user)
#   waf        (jiji-hamster, Python)  — ./waf configure build; system-wide via sudo ./waf install

TARGETS="upstream jiji jiji-activities jiji-do jiji-firefox-workspaces jiji-hamster jiji-hamster-bridge"

target_dir() {
    case "$1" in
        upstream)                echo "$WORKSPACE/repos/upstream/niri" ;;
        jiji)                    echo "$WORKSPACE/repos/jiji" ;;
        jiji-activities)         echo "$WORKSPACE/repos/jiji-activities" ;;
        jiji-do)                 echo "$WORKSPACE/repos/jiji-do" ;;
        jiji-firefox-workspaces) echo "$WORKSPACE/repos/jiji-firefox-workspaces" ;;
        jiji-hamster)            echo "$WORKSPACE/repos/jiji-hamster" ;;
        jiji-hamster-bridge)     echo "$WORKSPACE/repos/jiji-hamster-bridge" ;;
        *) return 1 ;;
    esac
}

# Single source of truth for how a target is built and installed. build.sh and
# install.sh both switch on this; nothing else classifies targets.
target_regime() {
    case "$1" in
        upstream|jiji) echo compositor ;;
        jiji-hamster)  echo waf ;;
        *)             echo cargo ;;
    esac
}

# Built binary name. Cargo tool targets use it for the cargo-install path and
# build-complete messaging; the waf target reports its installed entry point.
# Compositor targets are detected at install time instead (jiji post-rename,
# niri otherwise), so they are intentionally absent here.
target_bin() {
    case "$1" in
        jiji-activities)         echo "jiji-activities" ;;
        jiji-do)                 echo "jiji-do" ;;
        jiji-firefox-workspaces) echo "jiji-firefox-workspaces-host" ;;
        jiji-hamster)            echo "hamster" ;;
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
