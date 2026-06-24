#!/bin/sh
# Build, run, and profile jiji with Tracy.
#
# Tracy is a zone profiler split across TWO processes that must run at the same
# time:
#   * the CLIENT — instrumentation compiled into jiji (tracy_client::span!).
#     Zero-cost in a normal build; only active when jiji is built with a
#     profile-with-tracy* feature. The build / run / capture commands here are
#     what COMPILE and RUN that instrumented jiji.
#   * the SERVER — the Tracy GUI, or the headless tracy-capture tool. It connects
#     to the running client over a socket (127.0.0.1:8086) and records the trace.
#     The gui command builds and launches the GUI; it does NOT build or run jiji
#     (the GUI cannot launch jiji — it only attaches to an already-running one).
#
# "Profiling jiji" therefore always means running the instrumented jiji AND a
# server at the same time. Two ways to do that:
#   1. Headless, ONE terminal (simplest):  ./scripts/profile-jiji.sh capture
#   2. Live GUI, TWO terminals:            A: ./scripts/profile-jiji.sh gui
#                                          B: ./scripts/profile-jiji.sh run
#
# See docs/profiling-tracy.md for the full workflow and how to read the trace.
#
# Usage: ./scripts/profile-jiji.sh <command> [options]
#   build              compile the instrumented jiji binary (does NOT run it)
#   run [-- args]      run the instrumented jiji nested (builds first if missing)
#   capture [-o FILE]  record a headless trace: runs jiji + tracy-capture together
#   gui                build + launch the Tracy GUI (does NOT touch jiji)
#   help               print this guide (default when no command is given)
#
# Build options (for build / run / capture):
#   --ondemand       stream only while a server is attached (default)
#   --always-on      stream from process start (profile-with-tracy)
#   --allocations    also profile allocations (higher overhead)
#   --feature NAME   use an explicit feature name (overrides the above)
#
# Capture option:
#   -o FILE          output trace path (default: tmp/jiji-capture.tracy)
#
# Profiling-port option (run / capture):
#   --port N         Tracy port for the client + recorder (default 8086). Use a
#                    free port (e.g. --port 8087) if a long-running instrumented
#                    jiji — such as your session compositor — already holds 8086;
#                    otherwise the recorder connects to the wrong endpoint and hangs.
set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
JIJI_DIR="$WORKSPACE/repos/jiji"
BIN="$JIJI_DIR/target/release/jiji"
CAPTURE_BIN="$WORKSPACE/repos/tools/tracy/capture/build/tracy-capture"

# Print the header comment block (lines 2 until `set -e`) as the help text.
print_help() {
    sed -n '2,/^set -e/{/^set -e/d;p;}' "$0" | sed 's/^# \{0,1\}//'
}

# ── Parse command + options ──────────────────────────────────────────────────
CMD="${1:-help}"
[ $# -gt 0 ] && shift

FEATURE="profile-with-tracy-ondemand"
RUN_ARGS=""
CAPTURE_OUT="$WORKSPACE/tmp/jiji-capture.tracy"
PORT="8086"
while [ $# -gt 0 ]; do
    case "$1" in
        --ondemand)    FEATURE="profile-with-tracy-ondemand" ;;
        --always-on)   FEATURE="profile-with-tracy" ;;
        --allocations) FEATURE="profile-with-tracy-allocations" ;;
        --feature)     FEATURE="$2"; shift ;;
        -o)            CAPTURE_OUT="$2"; shift ;;
        --port)        PORT="$2"; shift ;;
        --)            shift; RUN_ARGS="$*"; break ;;
        -h|--help)     print_help; exit 0 ;;
        *)             echo "Error: unknown option '$1'." >&2; print_help >&2; exit 1 ;;
    esac
    shift
done

[ -d "$JIJI_DIR" ] || { echo "Error: $JIJI_DIR does not exist (run ./scripts/clone.sh)." >&2; exit 1; }

do_build() {
    echo "[profile-jiji] Compiling the INSTRUMENTED jiji (feature: $FEATURE)."
    echo "[profile-jiji]   A profiling build and a normal build share target/release/jiji,"
    echo "[profile-jiji]   so cargo recompiles the crate when you switch between them."
    echo "[profile-jiji]   Get a normal (non-instrumented) binary back with: ./scripts/build.sh jiji"
    cd "$JIJI_DIR"
    cargo build --release --features "$FEATURE"
    echo ""
    echo "[profile-jiji] Built: $BIN"
}

resolve_capture_bin() {
    [ -x "$CAPTURE_BIN" ] || CAPTURE_BIN="$(command -v tracy-capture 2>/dev/null || true)"
    [ -n "$CAPTURE_BIN" ] && [ -x "$CAPTURE_BIN" ] || {
        echo "Error: tracy-capture not found." >&2
        echo "Build the headless utils first: ./scripts/build-tracy.sh --utils --link" >&2
        exit 1
    }
}

# True if something is already LISTENing on the given TCP port. Used to fail fast
# rather than letting the recorder connect to a foreign endpoint and hang — the
# common case being an instrumented session jiji squatting on the default 8086.
port_in_use() {
    command -v ss >/dev/null 2>&1 || return 1   # can't tell; assume free
    ss -ltnH "sport = :$1" 2>/dev/null | grep -q .
}

case "$CMD" in
    build)
        do_build
        echo "[profile-jiji] Next: run it with './scripts/profile-jiji.sh run' (or 'capture')."
        ;;
    run)
        cat <<EOF
[profile-jiji] run = launch the instrumented jiji as a NESTED window (winit backend).
[profile-jiji]   This starts the CLIENT only. To get a trace, a SERVER must be attached:
[profile-jiji]     - headless: 'tracy-capture -o trace.tracy' in another terminal (or just
[profile-jiji]                 use './scripts/profile-jiji.sh capture' — one terminal), or
[profile-jiji]     - live GUI: './scripts/profile-jiji.sh gui', then click Connect -> localhost.
[profile-jiji]   With the on-demand feature jiji waits for a server; trace data only flows once
[profile-jiji]   you exercise the hot path (open the overview and type a query char by char).
[profile-jiji]   Tracy port: $PORT (server must attach to the same port).
[profile-jiji]   Close the jiji window (or Ctrl-C here) to stop.
EOF
        if port_in_use "$PORT"; then
            echo "[profile-jiji] WARNING: port $PORT is already in use — a server attaching to it" >&2
            echo "[profile-jiji]   may reach that other endpoint, not this jiji. If so, re-run both" >&2
            echo "[profile-jiji]   jiji and the server on a free port via --port N (e.g. --port 8087)." >&2
        fi
        # Build on demand so `run` works from a clean checkout.
        [ -x "$BIN" ] || do_build
        # The Tracy client in jiji reads TRACY_PORT for its listen port.
        export TRACY_PORT="$PORT"
        # No --session: jiji selects the windowed winit backend when a Wayland
        # session is present. Forward any extra args after `--`.
        # shellcheck disable=SC2086
        exec "$BIN" $RUN_ARGS
        ;;
    capture)
        resolve_capture_bin
        # Fail fast: if PORT is already taken (e.g. an instrumented session jiji on
        # the default 8086), tracy-capture would connect to that foreign endpoint
        # and hang forever instead of recording this nested jiji. Don't start.
        if port_in_use "$PORT"; then
            echo "Error: Tracy port $PORT is already in use." >&2
            echo "  A long-running instrumented jiji (e.g. your session compositor) likely holds it," >&2
            echo "  so the recorder would attach to the wrong endpoint and hang." >&2
            echo "  Re-run on a free port, e.g.: ./scripts/profile-jiji.sh capture --port 8087" >&2
            exit 1
        fi
        [ -x "$BIN" ] || do_build
        mkdir -p "$(dirname "$CAPTURE_OUT")"
        cat <<EOF
[profile-jiji] capture = record a headless trace in ONE terminal. Starts the
[profile-jiji]   tracy-capture SERVER and the instrumented jiji CLIENT together (port $PORT);
[profile-jiji]   the recorder connects automatically (no GUI, no Connect button).
[profile-jiji]   Output trace: $CAPTURE_OUT
[profile-jiji]   In the jiji window: open a few windows across activities, open the overview,
[profile-jiji]   type a query CHAR BY CHAR. Then CLOSE THE JIJI WINDOW (avoid Ctrl-C, so the
[profile-jiji]   recorder can finalize the file).
[profile-jiji]   Read it afterwards: tracy-csvexport --self "$CAPTURE_OUT"
EOF
        # tracy-capture polls 127.0.0.1:PORT until the client appears, so starting
        # it just before jiji is fine. -f overwrites any existing trace at the path.
        "$CAPTURE_BIN" -f -p "$PORT" -o "$CAPTURE_OUT" &
        cap_pid=$!
        # The Tracy client in jiji reads TRACY_PORT for its listen port.
        export TRACY_PORT="$PORT"
        # Run jiji in the foreground; the user drives the workload, then closes it.
        # shellcheck disable=SC2086
        "$BIN" $RUN_ARGS || true
        # jiji has exited — but tracy-capture will NOT notice on its own: jiji's
        # Tracy sockets lack FD_CLOEXEC, so every app spawned during the session
        # inherits the data connection and keeps it open after jiji dies. Its
        # `while(IsConnected())` loop would then spin forever. SIGINT is the
        # documented finalize signal — a connected recorder flushes and writes the
        # trace, a not-yet-connected one just terminates — so it always stops.
        echo "[profile-jiji] jiji exited; signalling tracy-capture to finalize the trace…"
        kill -INT "$cap_pid" 2>/dev/null || true
        # Hard backstop so the script can never hang if finalize itself wedges.
        ( sleep 60; kill -KILL "$cap_pid" 2>/dev/null ) & grace=$!
        wait "$cap_pid" 2>/dev/null || true
        kill "$grace" 2>/dev/null || true
        wait "$grace" 2>/dev/null || true
        if [ -s "$CAPTURE_OUT" ]; then
            echo "[profile-jiji] Trace saved: $CAPTURE_OUT"
            echo "[profile-jiji] Export the per-zone table: tracy-csvexport --self \"$CAPTURE_OUT\""
        else
            echo "[profile-jiji] No trace bytes written. If you saw a live 'Mbps … Tx' line the" >&2
            echo "[profile-jiji]   recorder was connected but couldn't finalize; otherwise it never" >&2
            echo "[profile-jiji]   connected on port $PORT. Re-run, or confirm with the GUI:" >&2
            echo "[profile-jiji]     term A: ./scripts/profile-jiji.sh gui   term B: ./scripts/profile-jiji.sh run --port $PORT" >&2
            exit 1
        fi
        ;;
    gui)
        cat <<EOF
[profile-jiji] gui = build (if needed) and launch the Tracy GUI — the profiler SERVER.
[profile-jiji]   This does NOT build or run jiji. The GUI connects to an already-running jiji
[profile-jiji]   over a socket; it cannot launch the compositor for you.
[profile-jiji]   This terminal will be taken by the GUI window. In ANOTHER terminal run:
[profile-jiji]       ./scripts/profile-jiji.sh run
[profile-jiji]   then in the GUI click Connect -> localhost (127.0.0.1) and drive the workload.
[profile-jiji]   For a no-GUI, one-terminal alternative, use './scripts/profile-jiji.sh capture'.
EOF
        # Build + symlink the GUI (no-op if already built), then launch it.
        sh "$WORKSPACE/scripts/build-tracy.sh" --link
        echo "[profile-jiji] Launching Tracy GUI — click Connect -> localhost."
        exec "$WORKSPACE/repos/tools/tracy/profiler/build/tracy-profiler"
        ;;
    help|-h|--help)
        print_help
        ;;
    *)
        echo "Error: unknown command '$CMD'." >&2
        print_help >&2
        exit 1
        ;;
esac
