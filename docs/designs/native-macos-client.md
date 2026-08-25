# Native macOS client

Design for a native macOS front end to throwntom, built on a Go daemon.
Decision record: [ADR-001](../adr/001-native-macos-client-over-daemon-api.md).

## Goals

- Menu bar countdown, keyboard-driven task window, launch at login,
  system notifications.
- All business logic stays in Go; Swift renders state and sends commands.
- The daemon API is transport-agnostic so a client on another device can
  be added later by binding the daemon to a network address.

Non-goals for this iteration: migrating the TUI onto the daemon, a
global hotkey, a command palette, stats view, Linux packaging, TCP
listener, authentication, in-app settings.

## Architecture

```
cmd/throwntom  (TUI) ──in-process──▶ internal/core ◀──in-process── cmd/throwntomd
                                                                        │ HTTP/JSON + SSE
                                                                   unix socket
                                                                        │
                                                            macos/Throwntom (SwiftUI)
```

Running the TUI and the daemon at the same time is unsupported: both
write the same session file.

## Go packages

### `internal/core`

The composition of `app.App`, scheduler, morning-reminder loop, snooze,
session persistence, event log and task store — everything currently in
`cmd/throwntom/timer_core.go` and `buildTimerCore` — moved here as
`core.Core` with constructor `core.New(cfg)`. Public methods are the
timer verbs (start, confirm, pause, resume, snooze, skip-today,
new-cycle), task operations, focus operations, and `Execute(line string)`
(the existing command-string dispatcher). The TUI keeps using it
in-process.

`Subscribe() (<-chan State, cancel func())` publishes a new `State` on
every state change: phase end, any verb, morning reminder firing, task or
focus change. Session is saved on every publish and on shutdown.

### `internal/daemon`

`net/http` handlers translating routes onto `core.Core`. No logic.
Defines the `State` document.

### `cmd/throwntomd`

Parse config, `core.New`, acquire single-instance lock, listen on the
socket, serve, save session and exit on `SIGTERM`/`SIGINT`.

### `tools/tomctl`

Stdlib CLI over the socket: `tomctl state`, `tomctl events`,
`tomctl cmd "<line>"`. Used for manual driving, integration tests and as
the Linux smoke test.

## API contract

Transport: HTTP/1.1 + JSON over a Unix socket at
`<config dir>/daemon.sock` (macOS: `~/Library/Application Support/throwntom/`).
A sibling lockfile is `flock`ed for single-instance; stale sockets are
removed after the lock is won.

| Method | Path | Meaning |
|---|---|---|
| `GET` | `/v1/state` | `State` document |
| `GET` | `/v1/events` | SSE stream; each event is a full `State` |
| `POST` | `/v1/command` | `{"line": "done 2"}` → `{"message": "..."}`; same grammar as the TUI |
| `POST` | `/v1/timer/{start,confirm,pause,resume,snooze,skip-today,new-cycle}` | Timer verbs |
| `GET`, `POST` | `/v1/tasks` | List active+completed; add |
| `POST` | `/v1/tasks/{id}/complete` | Complete |
| `DELETE` | `/v1/tasks/{id}` | Remove |
| `POST` | `/v1/tasks/clear-completed` | Clear |
| `GET` | `/v1/stats` | Analytics summary |

`State` document:

```json
{
  "state": "work",
  "phase_end_at": "2026-08-25T10:25:00Z",
  "paused_remaining": 0,
  "completed_today": 3,
  "work_sessions_in_block": 1,
  "long_break_every": 4,
  "next_stage": {"state": "short_break", "duration": 300},
  "morning_pending": false,
  "snooze_until": null,
  "status_line": "Work 12:34",
  "focused_task_ids": [3]
}
```

`status_line` is the same string the TUI shows; the core owns
presentation strings. Clients compute the live countdown locally from
`phase_end_at`; the daemon never emits per-second events.

Errors: `4xx` with `{"error": "..."}`. Invalid transitions (e.g. pause
while idle) return `409`. No silent no-ops.

## Daemon lifecycle on macOS

- launchd agent owns the daemon (`KeepAlive`, login launch,
  restart-on-crash). The plist and `throwntomd` binary are bundled inside
  the app; on first launch or when the socket is unreachable the app
  calls `SMAppService.agent(plistName:).register()`. The app never spawns
  the daemon directly, so there is exactly one way a daemon exists.
- `macos/agent.sh {install,uninstall}` installs a standalone plist for
  development without the app.
- The app itself is a login item via `SMAppService.mainApp`, toggled
  from the menu bar popover.
- Notifications and sound come from the daemon (`internal/notifier`).
  The app never notifies.

## macOS app

`LSUIElement` SwiftUI app in `macos/Throwntom/` (Xcode project).

### Surfaces

- **Menu bar extra** (`MenuBarExtra`, `.window` style). Title is
  `status_line`, countdown ticked locally at 1 Hz from `phase_end_at`.
  Popover shows state, next stage, focused tasks, and the
  context-relevant timer verbs as buttons with shortcut hints, plus the
  launch-at-login toggle.
- **Task window**. Transparent title bar, single-column list: active
  tasks, then completed tasks in a collapsed disclosure group. No
  sidebar. Toolbar mirrors the timer verbs with tooltips showing
  shortcuts.

### Input model

Every action exists graphically and has a shortcut, discoverable in the
application menu bar:

- *Timer*: Start `⌘R`, Confirm `⏎`, Pause/Resume `⌘P`, Snooze `⌘⇧S`,
  Skip Today.
- *Tasks*: New Task `⌘N` (inserts an editable row at the top; `⏎`
  commits), Complete `⌘⏎`, Delete `⌘⌫`, Focus `⌘F`, Move Up/Down
  `⌥↑/⌥↓`.
- `↑/↓` move the selection. `Esc` cancels an edit. `⌘W` closes the
  window. `⌘,` opens the config file in the default editor.

Each action resolves to a command string sent to `POST /v1/command`
(selecting row 3 and pressing `⌘⏌` sends `done 3`). The popover and the
window share one `Commands` definition.

### Data flow

One `@Observable` `DaemonClient` owns the SSE `URLSession` stream and
publishes `State`. It reconnects with backoff; on failure it registers
the launchd agent and shows "Starting timer…" in the menu bar. Views are
pure functions of `State`; the only local UI state is the selected row
and in-progress edit text.

## Repository layout

```
cmd/throwntom/        TUI
cmd/throwntomd/       daemon
internal/core/        Core + Subscribe
internal/daemon/      HTTP handlers, State, SSE
macos/Throwntom/      Xcode project
macos/build.sh        go build throwntomd → copy into bundle → xcodebuild
macos/agent.sh        standalone launchd plist install/uninstall
macos/README.md       build/run/register instructions
tools/tomctl/         daemon CLI
```

`go build ./...` and `go test ./...` never touch `macos/`.

## Testing

- Unit: `internal/core` (existing tests move with the code; `Subscribe`
  tested with a fake clock); `internal/daemon` with `httptest` against a
  real `Core` — no mocks of `Core`.
- Integration (`integration/`): socket + lock lifecycle, `tomctl`
  against a real daemon on a temp socket.
- Swift: `DaemonClient` decoding and reconnect under XCTest against a
  real `throwntomd` on a temp socket. No UI automation initially.
- CI: existing Go workflow unchanged; a macOS job (`macos/build.sh` +
  `xcodebuild test`) is added once the app exists.

## Delivery order

1. Move timer core into `internal/core` (pure move, TUI unchanged).
2. `Subscribe` on `Core`.
3. `internal/daemon`, `cmd/throwntomd`, single-instance lock, `tomctl`.
4. macOS menu bar app with `DaemonClient` and launchd registration.
5. macOS task window, menus, shortcuts.
6. macOS CI job.

## Risks

- Step 1 is the largest diff and touches working code; mitigated by
  being a move with the existing tests following it.
- `SMAppService` registration from an unsigned development build may
  prompt or require the app to live in `/Applications`; verify in step 4
  before building on it.
