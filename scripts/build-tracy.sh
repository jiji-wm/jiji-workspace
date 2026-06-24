#!/bin/sh
# Build the Tracy profiler GUI ("server") used to profile jiji.
#
# Tracy is not packaged in Debian, so the GUI is built from the source repo
# cloned at repos/tools/tracy. The clone is tag-pinned in repos.conf to the
# protocol bundled by jiji's tracy-client-sys (TracyVersion.hpp) — a mismatched
# GUI refuses to connect. This script single-sources that URL/tag from
# repos.conf so the pin lives in exactly one place.
#
# See docs/profiling-tracy.md for the full profiling workflow.
#
# Usage: ./scripts/build-tracy.sh [--link] [--clean] [--utils]
#   --link   symlink the built binary(ies) into ~/.local/bin (on PATH)
#   --clean  remove the build dir(s) first (force a clean configure/build)
#   --utils  also build the headless tracy-capture / tracy-csvexport tools
#
# tracy-capture records a trace to a .tracy file without the GUI, and
# tracy-csvexport dumps a saved trace's per-zone table as CSV. Together they
# make the profiling loop scriptable (capture -> export -> diff).
set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
TRACY_DIR="$WORKSPACE/repos/tools/tracy"
BUILD_DIR="$TRACY_DIR/profiler/build"
BIN="$BUILD_DIR/tracy-profiler"

# Let Tracy bundle its own capstone (the cmake default, DOWNLOAD_CAPSTONE=ON in
# cmake/vendor.cmake — a *pinned* GIT_TAG 6.0.0-Alpha5, fetched once via CPM).
# We cannot use the system capstone here: Tracy's server code (TracyWorker.cpp,
# AddSymbolCode) is written against the capstone 6.x API (CS_ARCH_AARCH64,
# detail.aarch64), but Debian ships capstone 5.x (CS_ARCH_ARM64, detail.arm64),
# so -DDOWNLOAD_CAPSTONE=OFF makes every rebuild — GUI *and* the headless utils —
# fail to compile. The GUI tag is protocol-locked to jiji's tracy-client-sys
# (see the version-lock note in docs/profiling-tracy.md), which transitively
# locks the capstone major version, so bundling is the only portable option
# until Debian carries capstone 6. The fetch needs network on a clean configure.
CMAKE_FLAGS="-DCMAKE_BUILD_TYPE=Release"

LINK=0
CLEAN=0
UTILS=0
for arg in "$@"; do
    case "$arg" in
        --link)  LINK=1 ;;
        --clean) CLEAN=1 ;;
        --utils) UTILS=1 ;;
        -h|--help)
            sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$arg'." >&2
            echo "Usage: $0 [--link] [--clean] [--utils]" >&2
            exit 1
            ;;
    esac
done

# Single-source the pinned URL/tag from repos.conf (group 'repos/tools', name 'tracy').
conf_line="$(awk -F'|' '
    { for (i=1;i<=NF;i++) gsub(/^[ \t]+|[ \t]+$/, "", $i) }
    $1 == "repos/tools" && $2 == "tracy" { print $3 "\t" $4 }
' "$WORKSPACE/repos.conf")"
TRACY_URL="$(printf '%s' "$conf_line" | cut -f1)"
TRACY_TAG="$(printf '%s' "$conf_line" | cut -f2)"

if [ -z "$TRACY_URL" ] || [ -z "$TRACY_TAG" ]; then
    echo "Error: no 'repos/tools | tracy' entry found in repos.conf." >&2
    exit 1
fi

# Build tools. The Wayland/EGL stack and capstone/freetype are required at
# configure time; pugixml and libcurl are optional (CPM downloads them if the
# system libs are absent). See docs/profiling-tracy.md for the apt list.
for tool in cmake ninja git; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Error: '$tool' not found. Install it (apt install cmake ninja-build git)." >&2
        exit 1
    }
done

# Clone at the pinned tag if absent (shallow — the GUI is version-frozen).
if [ ! -d "$TRACY_DIR/.git" ]; then
    echo "Cloning Tracy $TRACY_TAG -> $TRACY_DIR"
    git clone --depth 1 --branch "$TRACY_TAG" "$TRACY_URL" "$TRACY_DIR"
fi

# Report the version actually checked out, as a sanity check against the pin.
VER_HPP="$TRACY_DIR/public/common/TracyVersion.hpp"
if [ -f "$VER_HPP" ]; then
    ver="$(awk '/Major/{v=$0; gsub(/[^0-9]/,"",v); maj=v}
                /Minor/{v=$0; gsub(/[^0-9]/,"",v); min=v}
                /Patch/{v=$0; gsub(/[^0-9]/,"",v); pat=v}
                END{print maj"."min"."pat}' "$VER_HPP")"
    echo "Tracy GUI version: $ver (pinned $TRACY_TAG)"
fi

# build_component <src-subdir> <output-binary-name> <link-name>
# Configures + builds one CMake component under the Tracy tree and, with --link,
# symlinks its binary into ~/.local/bin under <link-name>.
build_component() {
    src="$TRACY_DIR/$1"
    out="$src/build/$2"
    link_name="$3"
    [ "$CLEAN" = 1 ] && rm -rf "$src/build"
    echo "Building $2 (release)..."
    # shellcheck disable=SC2086
    cmake -B "$src/build" -S "$src" -G Ninja $CMAKE_FLAGS
    cmake --build "$src/build" --parallel
    echo "Build complete: $out"
    if [ "$LINK" = 1 ]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$out" "$HOME/.local/bin/$link_name"
        echo "Linked: ~/.local/bin/$link_name -> $out"
    fi
}

build_component profiler tracy-profiler tracy

if [ "$UTILS" = 1 ]; then
    build_component capture   tracy-capture   tracy-capture
    build_component csvexport tracy-csvexport tracy-csvexport
fi

echo ""
if [ "$LINK" = 1 ]; then
    echo "Run 'tracy' to launch the GUI, then Connect to localhost."
    if [ "$UTILS" = 1 ]; then
        echo "Headless: tracy-capture -o trace.tracy   |   tracy-csvexport trace.tracy"
    fi
else
    echo "Run the GUI with: $BIN"
    echo "(Pass --link to put 'tracy' on your PATH; --utils to also build the CLI tools.)"
fi

# Exit 0 explicitly: the script's last command must not leave a non-zero status
# (e.g. a short-circuited `&&` test), or callers under `set -e` — like
# profile-jiji.sh's `gui` command — abort before launching the GUI.
exit 0
