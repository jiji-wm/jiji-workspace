# Profiling jiji with Tracy

[Tracy](https://github.com/wolfpld/tracy) is a frame profiler. We use it to find
which stage of a hot path dominates — e.g. the per-keystroke
`Niri::dispatch_overview_search` work behind the overview omnibar.

The instrumentation in jiji is **zero-cost when off**: `tracy-client` is pulled
in with `default-features = false`, so `tracy_client::span!` expands to nothing
in a normal build. It only "turns on" when you compile jiji with a
`profile-with-tracy*` feature. That is why a normal `cargo build --release`
(and CI) never pays for the spans.

## Quick start

Tracy is **two processes that must run at once**: the *client* (instrumentation
compiled into jiji) and a *server* (the GUI or the headless `tracy-capture`) that
attaches to it over a socket. The GUI never launches jiji — you run jiji yourself
and the server connects to it.

Simplest — one terminal, headless capture straight to a file:

```sh
./scripts/profile-jiji.sh capture   # runs jiji + tracy-capture together; writes a .tracy
```

Drive the workload (§3) in the jiji window, then **close the window** — the trace
lands at `tmp/jiji-capture.tracy`. Read it with `tracy-csvexport --self`
(§5).

Live exploration in the GUI — two terminals (the `gui` command blocks its own):

```sh
./scripts/profile-jiji.sh gui     # term A: build + launch Tracy (server only)
./scripts/profile-jiji.sh run     # term B: build + run the instrumented jiji (client)
```

Then click **Connect → localhost** in the GUI and read the trace (§4). Each
command prints what it does (and does not do) when you run it; `help` prints the
full guide. The sections below explain every piece and the version-lock that ties
the GUI to the compositor.

## The version-lock invariant

The Tracy **GUI** and the **client** baked into jiji must speak the same
protocol, or Tracy refuses to connect ("protocol mismatch"). The authoritative
version is `TracyVersion.hpp` bundled inside jiji's `tracy-client-sys`
dependency. The GUI clone is therefore **tag-pinned** in `repos.conf`:

```
repos/tools | tracy | https://github.com/wolfpld/tracy.git | v0.13.1 | github
```

`scripts/build-tracy.sh` reads that line, so the pin lives in exactly one place.
When jiji bumps `tracy-client-sys`, check the new bundled version and update the
tag in `repos.conf` — nothing else needs to change.

## 1. Build the Tracy GUI

Tracy is not packaged in Debian, so the GUI is built from source:

```sh
./scripts/build-tracy.sh          # build only
./scripts/build-tracy.sh --link   # build + symlink to ~/.local/bin/tracy
./scripts/build-tracy.sh --clean  # wipe the build dir first
```

The script clones the repo at the pinned tag if it is missing, builds the
release profiler (Wayland backend, the Linux default), and reports the binary at
`repos/tools/tracy/profiler/build/tracy-profiler`.

### Build dependencies

All hard-required deps for the Wayland backend are part of the standard jiji
build environment (see `INSTALL-debian.md`): the Wayland/EGL/xkbcommon stack,
plus `libfreetype-dev`, `libdbus-1-dev`, `cmake`, `ninja-build`. GLFW and X11 are
**not** needed (those are the legacy `-DLEGACY` backend only).

**Capstone is bundled, not taken from the system.** Tracy's CMake fetches a
pinned capstone (`6.0.0-Alpha5`) via CPM at configure time. We deliberately do
*not* pass `-DDOWNLOAD_CAPSTONE=OFF`: Tracy 0.13.1's server code
(`TracyWorker.cpp`) is written against the capstone 6.x API (`CS_ARCH_AARCH64`,
`detail.aarch64`), but Debian ships capstone 5.x (`CS_ARCH_ARM64`,
`detail.arm64`), so forcing the system lib breaks the build (GUI *and* the
headless utils). Because the GUI tag is protocol-locked to jiji's
`tracy-client-sys` (see the version-lock note above), the capstone major version
is locked with it — bundling is the only portable option until Debian carries
capstone 6. So `libcapstone-dev` is **not** required.

Two libs are optional — if absent, Tracy's CMake (CPM) downloads and builds them
at configure time, so the build still succeeds; installing them just avoids the
download:

```sh
sudo apt install libpugixml-dev libcurl4-openssl-dev
```

> **Troubleshooting — `git@github.com: Permission denied (publickey)` during the
> build.** Tracy's CPM/FetchContent clones some deps (e.g. imgui) over `https`.
> If your `~/.gitconfig` rewrites GitHub https→ssh
> (`url."git@github.com:".insteadOf "https://github.com/"`), those clones become
> ssh and fail in any context without a working ssh key/agent. Run the build in
> a shell where ssh works, or neutralise the rewrite for the build only:
> `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null ./scripts/build-tracy.sh …`

## 2. Build jiji with the on-demand Tracy feature

```sh
./scripts/profile-jiji.sh build            # default: profile-with-tracy-ondemand
./scripts/profile-jiji.sh build --always-on
./scripts/profile-jiji.sh build --allocations
```

Under the hood this is `cargo build --release --features <feature>` in
`repos/jiji`, producing `repos/jiji/target/release/jiji`.

Use the on-demand variant (the default): jiji runs at full speed and only starts
streaming once the profiler attaches, so you pay no overhead until you connect.
The build is always **release** — a debug build's per-frame `verify_invariants`
chain would swamp the profile and misattribute cost.

Feature variants (all defined in `repos/jiji/Cargo.toml`, selectable via the
flags above or `--feature NAME`):

| Feature | Flag | Use |
|---|---|---|
| `profile-with-tracy-ondemand` | `--ondemand` (default) | Streams only while the profiler is attached (preferred). |
| `profile-with-tracy` | `--always-on` | Always-on streaming from process start. |
| `profile-with-tracy-allocations` | `--allocations` | Adds allocation profiling (higher overhead). |

A profiling build and a normal build share `target/release/jiji`; cargo
recompiles the crate when you switch feature sets. Re-run `./scripts/build.sh
jiji` to get a non-instrumented binary back.

## 3. Run jiji and generate the workload

Inside an existing Wayland session, jiji auto-picks the winit backend and opens
as a nested window:

```sh
./scripts/profile-jiji.sh run        # builds first if needed, then runs nested
```

This runs the binary without `--session`, so jiji selects the windowed winit
backend. Extra arguments are forwarded after `--` (e.g.
`./scripts/profile-jiji.sh run -- --config /path/to/config.kdl`).

To exercise `dispatch_overview_search` (one umbrella span per omnibar keystroke,
with five children): open a few windows across a couple of activities so the
snapshot walks have real work, open the overview, and type a query into the
omnibar character by character.

## 4. Connect and read which stage dominates

Launch the GUI (`tracy` if you used `--link`, else the printed path) → **Connect**
to `localhost`. With the on-demand build it attaches live; keep typing to feed it
frames. Then:

- Find the `Niri::dispatch_overview_search` zone (the umbrella).
- Open **Statistics** (or right-click the zone → Statistics) for total/mean
  self-time per zone aggregated across every keystroke — far more reliable than
  eyeballing one frame.
- Compare the five children: collect activity/workspace snapshots, collect
  window snapshot, drive_search, build_completions, snap + session update.

Whichever child carries the largest total/self-time tells you what to optimise
(cache the snapshot, pre-lowercase haystacks, go async, …) with real data rather
than a guess.

> Saving from the GUI: Tracy has no File menu. The **Save trace** action lives
> under the leftmost **connection icon** dropdown (the one that shows the live
> link), and only after the client has disconnected. For a repeatable baseline,
> prefer the headless capture below.

## 5. Headless capture and CSV export (repeatable / before-after)

The GUI is fine for exploring, but for a reproducible before/after the
command-line tools are better — they record straight to a file and export the
same per-zone table as CSV. Build them once:

```sh
./scripts/build-tracy.sh --utils --link
```

Capture a session to a file (start the recorder first; it waits for a
connection, then streams until jiji exits or you Ctrl-C):

```sh
tracy-capture -o overview-before.tracy &   # waits for the client
./scripts/profile-jiji.sh run              # drive the workload, then quit jiji
```

Export the per-zone table (this is what the GUI's Statistics view shows):

```sh
tracy-csvexport --self overview-before.tracy
```

`--self` reports self-time (work in the zone excluding children) — the right
metric for comparing the `dispatch_overview_search` children. Keep the `.tracy`
file as the baseline; after the optimisation lands, capture `overview-after.tracy`
the same way and diff the two CSVs. Save captures outside version control (the
`repos/` tree is already gitignored, or use any scratch path) — traces are large
binaries.
