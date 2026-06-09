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
cargo build --release

if target_is_compositor "$TARGET"; then
    # Binary name follows the fork's [package] name. Upstream and pre-rename
    # jiji both produce 'niri'; post-compositor-rename jiji produces 'jiji'.
    for name in jiji niri; do
        if [ -f "$DIR/target/release/$name" ]; then
            echo ""
            echo "Build complete: $DIR/target/release/$name"
            break
        fi
    done
else
    BIN="$(target_bin "$TARGET")"
    echo ""
    echo "Build complete: $DIR/target/release/$BIN"
fi
echo "Run ./scripts/install.sh $TARGET to install."
