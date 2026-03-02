# New Cycle Command Design

## Summary
Add a daemon command that starts a new pomodoro cycle immediately, resetting only cycle-progress (`pomodoros=x/y`) while preserving today's total completed pomodoros.

## Goals
- Provide an explicit user action to begin a fresh cycle at any time.
- Reset long-break block progress to `0/<long_break_every>`.
- Preserve `today's pomodoros` count.
- Start a work session immediately.

## Non-Goals
- No changes to existing `start` command semantics.
- No changes to schedule behavior.
- No additional third-party dependencies.

## Architecture
- Introduce an engine-level operation that resets cycle block progress without clearing the daily total.
- Expose an app-level operation that stops active timer/reminders, resets runtime timer metadata, and starts a new work period through the engine.
- Wire a new daemon command handler `new-cycle` to call that app operation.

## Components
- `internal/engine/engine.go`
- `internal/app/app.go`
- `cmd/throwntom/daemon_core.go`
- Tests in matching packages plus README coverage test updates.

## Data and State Flow
1. User sends `new-cycle` via `throwntom shell` or `throwntom ctl new-cycle`.
2. Daemon command handler invokes `App.StartNewCycle()`.
3. App stops reminder loop and active timer, clears paused metadata, and calls engine new-cycle start.
4. Engine sets state to work and resets block progress only.
5. App starts a fresh work timer and status reflects `pomodoro ... pomodoros=0/<every>` while retaining `today's pomodoros=<existing>`.

## Error Handling
- `new-cycle` is a local state transition; no new error paths expected.
- Unknown command behavior remains unchanged.

## Testing Strategy
- Unit tests first (TDD Red/Green) at engine/app/daemon layers.
- Verify block reset and daily total preservation.
- Verify command wiring/help text and README command list.
- Run focused tests during red/green, then full `go test -timeout 30s ./...`.

## Risks
- Accidental reset of `completedToday` if implementation reuses full day reset logic.
- Timer/reminder leakage if current session isn’t fully stopped before restarting.

## Mitigations
- Dedicated tests that assert `today's pomodoros` remains unchanged across `new-cycle`.
- App-level tests ensure post-command state is work/pomodoro with reset cycle progress.
