# Native macOS client

Design for a native macOS front end to throwntom, built on a Go daemon.
Decision records: [ADR-001](../adr/001-native-macos-client-over-daemon-api.md)
(daemon + native client), [ADR-002](../adr/002-macos-client-transport-over-unix-socket.md)
(client transport), [ADR-005](../adr/005-single-window-macos-client.md)
(single phase-coloured window), [SwiftPM bundle](../decisions/macos-app-swiftpm-bundle.md)
(build system).

## Goals

- One window that is the whole app: a regular Dock application reached
  by ⌘-Tab or a Dock click, parked wherever the user likes, and loud
  about which phase the timer is in. The flow it serves is: hear the
  sound or see the notification → ⌘-Tab to the window → act with a
  shortcut or a button.
- Every action is keyboard-driven and every shortcut is visible where
  the action is.
- Launch at login, system notifications.
- All business logic stays in Go; Swift renders state and sends commands.
- The daemon API is transport-agnostic so a client on another device can
  be added later by binding the daemon to a network address.

Non-goals: a menu bar item (tried and removed — the countdown was never
looked at and a control popover in the corner of a large display is the
wrong place to act), a global hotkey, a command palette, a typed command
prompt, migrating the TUI onto the daemon, Linux packaging, TCP
listener, authentication, in-app settings. Noted follow-ups, not in this
design: the tomato mascot in the slot reserved for it, and floating the
window above others while a phase awaits confirmation.

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
`~/.config/throwntom/daemon.sock` (the directory the TUI already uses for config, tasks and session).
A sibling lockfile is `flock`ed for single-instance; stale sockets are
removed after the lock is won.

| Method | Path | Meaning |
|---|---|---|
| `GET` | `/v1/state` | `State` document |
| `GET` | `/v1/events` | SSE stream; each event is a full `State` |
| `POST` | `/v1/command` | `{"line": "done 2"}` → `{"message": "..."}`; same grammar as the TUI |
| `POST` | `/v1/timer/{start,confirm,pause,resume,snooze,skip-today,new-cycle}` | Timer verbs; `snooze` takes `{"minutes": N}`. `start`/`confirm` never wait on the TUI's task-focus prompt: the daemon answers it with an empty line, so focus is set via `/v1/command` or task routes instead |
| `GET`, `POST` | `/v1/tasks` | List active+completed; add |
| `POST` | `/v1/tasks/{id}/complete` | Complete |
| `DELETE` | `/v1/tasks/{id}` | Remove |
| `POST` | `/v1/tasks/clear-completed` | Clear |
| `GET` | `/v1/stats` | Analytics summary |

`State` document:

```jsonc
{
  "state": "work",
  "phase_end_at": "2026-08-25T10:25:00Z",
  "paused_remaining": 0,          // seconds
  "completed_today": 3,
  "work_sessions_in_block": 1,
  "long_break_every": 4,
  "next_stage": {"state": "short_break", "duration": 300},  // seconds
  "morning_pending": false,
  "snooze_until": null,
  "status_line": "Work 12:34",
  "focused_task_ids": [3]
}
```

`snooze_until` is the morning-reminder snooze deadline (null when no
morning snooze is active). `status_line` is the same string the TUI shows; the core owns
presentation strings. Clients compute the live countdown locally from
`phase_end_at`; the daemon never emits per-second events.

Errors: `4xx` with `{"error": "..."}`. The core classifies every command
failure as usage (unknown command, missing or unparseable argument,
out-of-range position) or refused (a valid command the current state does not
allow), and the daemon maps usage to `400` and refused to `409`. Invalid
transitions (e.g. pause while idle) are refusals, so they return `409`. No
silent no-ops.

## Daemon lifecycle on macOS

- launchd agent owns the daemon (`KeepAlive`, login launch,
  restart-on-crash). The plist and `throwntomd` binary are bundled inside
  the app; on first launch or when the socket is unreachable the app
  calls `SMAppService.agent(plistName:).register()`. The app never spawns
  the daemon directly, so there is exactly one way a daemon exists.
- `macos/agent.sh {install,uninstall}` installs a standalone plist for
  development without the app.
- The app itself is a login item via `SMAppService.mainApp`, toggled
  from the application menu.
- Quitting the app (`⌘Q`) leaves the daemon running under launchd.
  Stopping, restarting and config reload are a separate decision
  (throwntom-9ig.2).
- Notifications and sound are the client's job (ADR-003); the daemon
  only emits state.

## macOS app

Regular (Dock, ⌘-Tab) SwiftUI app in `macos/Throwntom/`, a Swift
Package with a library target (`ThrowntomClient`: transport,
`DaemonClient`, `State`, `Commands`), a UI target (`ThrowntomUI`: views,
menus, palette) and the executable. `macos/build.sh` assembles and
ad-hoc signs the bundle; there is no Xcode project.

### The window

There is exactly one window. Its ground colour is the timer phase, so
which phase the user is in reads from across the room; its content, top
to bottom:

1. Hidden title bar; the top of the window is the drag zone.
2. **Timer header**: the *mascot slot* (a cream rounded square holding
   the phase glyph — 🍅 work, ☕ short break, 🌿 long break, 🌱 idle,
   🔔 awaiting confirm, SF `pause.fill` paused — sized at ~72pt for the
   mascot that replaces the glyph later) beside the phase name in large
   bold type and the countdown in tabular figures, ticked locally at
   1 Hz from `phase_end_at`.
3. **Tomato garden**: today's completed pomodoros as 🍅 glyphs grouped
   into blocks of `long_break_every`, blocks flowed to the window width
   like words; the unfilled slots of the current block are dimmed, so
   progress toward the long break is visible. Under it, the line
   `N today · M blocks done`.
4. **Action chips**: the timer verbs valid in the current state
   (`TimerActions.available`), each a chip with its shortcut in
   trailing monospace text. The primary verb (Start, Confirm, Resume)
   is a dark chip; the rest are translucent.
5. **Focus**: the focused tasks, or nothing when none are focused.
6. **Tasks panel** (`⌘T`) and **Stats panel** (`⌘⇧D`), one at a time,
   expanding the window downward; the same key or `Esc` collapses it.
   Panels start closed on every launch. The tasks panel is the
   single-column list: active tasks, then completed tasks in a
   collapsed disclosure group, a hint line of the task shortcuts under
   it, and a per-row context menu carrying the same actions. The stats
   panel is the `/v1/stats` summary as a two-column key/value grid:
   today, this week, this month, all time, streak, best hour.
7. Reminder banner and daemon/permission errors, when present, sit
   between the chips and the focus section so they are never hidden by
   a panel.

The window remembers its frame between launches. Its minimum width fits
the header and one block of tomatoes.

Before the daemon has sent state, and while reconnecting, the same
layout renders on a neutral dark ground with the `ConnectionStatus`
placeholder in the header; the window never goes blank.

### Attention

At the end of a phase the client posts the notification and sound,
requests user attention (Dock bounce), and the window recolours to the
awaiting-confirm ground with the slot pulsing (not under Reduce
Motion). The window never activates itself.

### Visual system

Colour lives in `Palette.swift`, keyed by `DaemonState.Phase`, and is documented in
`DESIGN.md` as the `macos-*` tokens; a Swift test asserts every text on
ground, chip on ground and chip-text on chip pairing meets WCAG AA
(4.5:1), mirroring the Go palette test. The look is the same in light
and dark system appearance. Grounds are mid-tone jewel versions of the
TUI state colours; text is the dark ink; cream on the disconnected ground
and inside panels; the primary chip is the icon's outline brown with
cream text; the slot is cream.

Type is the system font: phase name `.largeTitle` bold, countdown
`.title2`, body and caption elsewhere. Radii: slot 10pt, chips 6pt,
panels 8pt. Ground colour changes and panel expansion animate over
250 ms ease-out.

### Input model

Every action exists graphically, is keyboard-accessible, and is
discoverable in the menu bar; only some actions have a direct shortcut:

- *Timer menu*: Start `⌘R`, Confirm `⏎`, Pause/Resume `⌘P`, Snooze
  `⌘⇧S`, Skip Today, New Cycle (the last two deliberately have no
  shortcut).
- *View menu*: Tasks `⌘T`, Stats `⌘⇧D`, Keyboard Shortcuts `⌘/` (a
  sheet listing everything). `Esc` closes an open panel or sheet.
- *Tasks menu*: New Task `⌘N` (inserts an editable row at the top; `⏎`
  commits, `Esc` cancels), Complete `⌘⏎`, Delete `⌘⌫`, Focus `⌘F`, Move
  Up/Down `⌥↑/⌥↓`. `↑/↓` move the selection.
- *Application menu*: Open Config File… `⌘,`, Launch at Login (toggle),
  Open Notification Settings…, Open Login Items Settings…, Quit `⌘Q`.

Each Timer action calls its dedicated `POST /v1/timer/{verb}` route.
Each Tasks action but New Task (which only opens the inline editor)
resolves to a command string sent to `POST /v1/command` (selecting row
3 and pressing `⌘⏎` sends `task done 3`). View and Application menu
actions are local app or system operations — panel toggles, settings,
login-item controls, Quit — and never reach the daemon. Menus, chips
and the context menu share one `MenuModel` so titles and shortcuts
have a single source.

### Data flow

One `@Observable` `DaemonClient` owns the SSE stream and publishes
`State`. It reconnects with backoff; on failure it registers the launchd
agent and the header shows "Starting timer…". `DaemonClient.stats()`
fetches `/v1/stats` when the stats panel opens. Views are pure functions
of `State`; the only local UI state is which panel is open, the selected
row and in-progress edit text. A `MainWindowContent` value computes
what the window shows for a given `State`, connection and panel state,
so those rules are unit-tested without SwiftUI.

### UI files

```
ThrowntomUI/
  ThrowntomApp, ThrowntomScenes      one Window scene and its .commands
  MainWindow, MainWindowContent      composition; pure "what shows" value
  TimerHeader, MascotSlot            slot + phase + countdown
  TomatoGarden, BlockFlowLayout       (done, in-block, every) → blocks; blocks → wrapped rows
  ActionChips, Chip
  FocusSection
  TasksPanel, TaskRow, NewTaskRow, TaskContextMenu
  StatsPanel
  ShortcutSheet
  Palette                            phase → colours
  AppMenus, MenuModel
  ReminderBanner, ReminderResponder, NotificationAdapters
```

`URLSession` cannot reach a Unix socket, so the client carries its own
transport (ADR-002): a `DaemonTransport` protocol (`request` returning
`(status, body)`, `events` returning `AsyncThrowingStream<Data, Error>`)
with one implementation, `UnixSocketTransport`, built on `NWConnection`
to `NWEndpoint.unix(path:)` plus a minimal HTTP/1.1 parser (status line,
headers, `Content-Length` and chunked bodies) and an SSE frame splitter.
The parser is pure over `Data`, bounds header and frame sizes, and throws
on malformed input. The app is not sandboxed. A TCP transport with
authentication is a later addition behind the same protocol.

## Repository layout

```
cmd/throwntom/        TUI
cmd/throwntomd/       daemon
internal/core/        Core + Subscribe
internal/daemon/      HTTP handlers, State, SSE
macos/Throwntom/      Swift package (ThrowntomClient lib + Throwntom app)
macos/build.sh        go build throwntomd → swift build → assemble + sign .app
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
- Swift, client: HTTP/SSE parsing as pure unit tests;
  `UnixSocketTransport` and `DaemonClient` decoding, `stats()` and
  reconnect under XCTest against a real `throwntomd` on a temp socket.
- Swift, UI: pure unit tests for `TomatoGarden` blocks (0, 3, 4, 11, 23
  pomodoros) and `BlockFlowLayout` row wrapping at several widths,
  `Palette` AA contrast for every pairing, `MenuModel` including the
  View menu, `StatsSummary` decoding of a captured
  `/v1/stats` body, and `MainWindowContent` for connected, connecting,
  reconnecting and panel-open states. No UI automation; the
  `swift-review` and `ux-audit` skills gate the branch, then a manual
  drive (`macos/build.sh`, quit, bootout, reopen).
- CI: Go workflow unchanged; the macOS job builds the bundle and runs
  `swift test`.

## Delivery order

1. `Phase`, `Palette` with the contrast test, `DESIGN.md` tokens.
2. `TomatoGarden`, `MainWindowContent`, `MenuModel.view`.
3. `DaemonClient.stats()` and `StatsSummary`.
4. Window scene: header, garden, chips, focus; drop `LSUIElement` and
   the menu bar extra; delete the popover and task window.
5. Tasks panel with context menu and hint line; stats panel; shortcut
   sheet.
6. Attention: Dock bounce and awaiting-confirm pulse.

## Risks

- Step 4 replaces every view at once; mitigated by steps 1–3 landing
  the pure, tested pieces first and by `ThrowntomClient` not changing
  shape.
- A phase-coloured window is a strong look; if a jewel ground proves
  tiring over a full day the palette is one file and one test away from
  a paler variant.
- `SMAppService` agent registration from a development build is safe:
  an ad-hoc signature is enough, the bundle need not live in
  `/Applications`, and the user sees a notification rather than a prompt.
  Measured in
  [docs/spikes/smappservice-agent-registration](../spikes/smappservice-agent-registration/result.md),
  which also records the dev-loop caveat that rebuilding in place does not
  restart the agent.
