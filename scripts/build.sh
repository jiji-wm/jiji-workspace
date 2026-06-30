#!/bin/sh
set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
. "$WORKSPACE/scripts/project-targets.sh"

case "${1:-}" in
    --targets)
        print_targets
        exit 0
        ;;
esac

TARGET="${1:-upstream}"
if ! DIR="$(target_dir "$TARGET")"; then
    usage_targets "$0"
    exit 1
fi

if [ ! -d "$DIR" ]; then
    echo "Error: $DIR does not exist." >&2
    exit 1
fi

echo "Building $TARGET (release)..."
cd "$DIR"

case "$(target_regime "$TARGET")" in
    waf)
        # Python/GTK fork (hamster): waf bundles its own build. Configure +
        # build as the user; install.sh runs the system-wide `sudo ./waf install`.
        ./waf configure build
        echo ""
        echo "Build complete (waf): $DIR/build"
        ;;
    compositor)
        cargo build --release
        # Binary name follows the fork's [package] name. Upstream and pre-rename
        # jiji both produce 'niri'; post-compositor-rename jiji produces 'jiji'.
        for name in jiji niri; do
            if [ -f "$DIR/target/release/$name" ]; then
                echo ""
                echo "Build complete: $DIR/target/release/$name"
                break
            fi
        done
        ;;
    cargo)
        cargo build --release
        BIN="$(target_bin "$TARGET")"
        echo ""
        echo "Build complete: $DIR/target/release/$BIN"
        ;;
esac
echo "Run ./scripts/install.sh $TARGET to install."
