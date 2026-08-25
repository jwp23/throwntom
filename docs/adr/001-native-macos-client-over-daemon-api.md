# ADR-001: Native macOS client over a Go daemon API

## Context

throwntom is a Go pomodoro timer with a Bubble Tea TUI. We want a native
macOS experience: a menu bar countdown, a keyboard-driven task window,
launch at login, and system notifications. Longer term, we want the timer
to run in one place (a desk machine) and be controllable from another
device (a phone during a break).

The business logic (`internal/engine`, `internal/app`) is already
UI-agnostic and stdlib-only. Some orchestration (scheduler, morning
reminders, snooze) currently lives in `cmd/throwntom/timer_core.go`.

Options considered:

1. Go daemon exposing an HTTP/JSON API; SwiftUI app as a client.
2. SwiftUI app spawning the Go binary and speaking JSON-RPC over stdio.
3. Go core compiled as a cgo static library linked into the Swift app.
4. A Go-only GUI toolkit (Fyne, Wails, systray) to keep one toolchain.

## Decision

Option 1. A long-running Go daemon (`throwntomd`, launchd agent) owns the
timer, scheduler and reminders and exposes a transport-agnostic JSON API
(request/response plus a state-change stream). The macOS app is a thin
SwiftUI/AppKit client: menu bar item plus task window, all logic remains
in Go. The API contract is designed so the daemon can later bind to a LAN
address and serve a client on another device (form of that client left
open) without redesign.

The existing TUI keeps running in-process against `internal/app` for now;
migrating it to the daemon API is deferred.

The Swift project lives in this repository (`macos/`), not a new one. The
Go core, its tests and the API contract live here; splitting repos would
require versioning a protocol before it exists.

## Trade-offs

- Two toolchains (Go + Xcode). Accepted: native feel is the point of the
  experiment, and the alternative (option 4) is not native. Only the
  business logic must never be duplicated; the boundary enforces that.
- A real daemon (launchd plist, single-instance, lifecycle) is more
  operational surface than options 2/3. Required anyway for "timer keeps
  running while the window is closed" and login launch.
- Options 2 and 3 are single-client and foreclose the multi-device goal.
- Deferring the TUI migration means two code paths drive `internal/app`
  temporarily; the orchestration in `cmd/throwntom/timer_core.go` must
  move into `internal/` so the daemon and TUI share it rather than fork it.
