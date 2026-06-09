# Compositor Architecture (key concepts)

These notes help when modifying the compositor source in `repos/jiji/` or `repos/upstream/niri/`. They describe the post-Phase-0b-2 layout shape. The compositor source rename has landed: the sub-crates are `jiji-ipc`, `jiji-config`, `jiji-visual-tests` and the binary is `jiji`.

## Crate structure
- **`jiji-ipc`** — IPC protocol types (`Request`, `Response`, `Action`, `Event`, `Workspace`, `Window`). This is the public API contract. Lives in `jiji-ipc/src/lib.rs`.
- **`jiji-config`** — KDL config parsing. Window rules in `src/window_rule.rs`, workspace config in `src/workspace.rs`. Config types defined here, consumed by the main crate.
- **`jiji`** (the binary crate) — Compositor logic. Layout in `src/layout/`, IPC server in `src/ipc/server.rs`, input dispatch in `src/input/mod.rs`.

## Layout hierarchy

Post-Phase-0b-2 shape (see the DD for history). Workspace storage is a flat pool on `Layout`; monitors hold an ordered view of `WorkspaceId`s rather than owning `Workspace` values.

```
Layout<W>
  ├─ workspaces: HashMap<WorkspaceId, Workspace<W>>   (canonical pool, sub-step 3a)
  ├─ monitors: Vec<Monitor<W>>                         (flat field; MonitorSet dropped in 3d)
  ├─ primary_idx / active_monitor_idx: usize
  └─ disconnected_workspace_ids: Vec<WorkspaceId>      (populated iff monitors.is_empty())

Monitor (one per output, indexed into Layout.monitors)
  ├─ view: WorkspaceView { ids: Vec<WorkspaceId>, active, previous, ... }  (Phase 0b-1)
  └─ WorkspaceSwitch (animation/gesture state)

Workspace<W> (owned by Layout.workspaces pool)
  ├─ ScrollingSpace (tiled columns + ViewOffset for horizontal scroll)
  │    └─ Column → Tile<W> (windows)
  └─ FloatingSpace (positioned floating tiles)
```

## Key ID types
- `WorkspaceId(u64)` — stable, never reused, global counter. Exposed as `u64` in IPC.
- `MappedId(u64)` — window ID, same pattern. Exposed as `u64` in IPC.
- `OutputId(String)` — make+model+serial or connector name. Used for workspace-output binding on reconnect.

## IPC protocol
- Socket at `$JIJI_SOCKET`. JSON lines, one request → one reply.
- `Request::EventStream` switches to continuous event mode (no more request/reply).
- Event stream sends full state on connect (`WorkspacesChanged`, `WindowsChanged`, etc.), then incremental updates.
- `EventStreamState` (in `jiji-ipc/src/state.rs`) is a client-side state tracker that applies events.

## Workspace switching internals
- Active / previous workspace per monitor lives in `Monitor.view: WorkspaceView`. Navigation helpers like `view.activate()`, `view.position_of(id)` replaced the pre-0b-1 `active_workspace_idx` / `previous_workspace_id` fields.
- Activating a workspace starts a `WorkspaceSwitch::Animation`. Fractional workspace indices during animation/gesture enable smooth vertical transitions.
- `ViewOffset` in `ScrollingSpace` is horizontal scroll (separate from vertical workspace switch).

## Window rules
- Defined in config as `window-rule { match ...; property ...; }`.
- `Match` struct supports: `app_id`, `title`, `is_active`, `is_focused`, `is_floating`, `is_urgent`, `at_startup`.
- Properties: `open-on-output`, `open-on-workspace`, `open-maximized`, `open-floating`, `opacity`, `block-out-from`, etc.
