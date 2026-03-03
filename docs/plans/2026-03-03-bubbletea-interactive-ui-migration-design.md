# Bubble Tea Interactive UI Migration Design

Date: 2026-03-03

## Summary
Adopt Bubble Tea as a well-scoped UI dependency for interactive terminal modes, using an incremental migration that replaces raw terminal input and ANSI redraw plumbing first while preserving existing command/control callbacks and daemon behavior. Stability is prioritized over dependency minimization.

## Goals
- Eliminate regressions caused by manual terminal cursor control and resize handling.
- Preserve the existing 3-line UI contract:
  1. `status: ...`
  2. `message: ...`
  3. `command> ...`
- Keep 1-second status refresh behavior.
- Keep daemon command semantics unchanged.
- Limit dependency scope to UI runtime concerns.

## Non-Goals
- Reworking engine/scheduler/reminder domain logic.
- Expanding input capabilities beyond current scope (history, arrow navigation).
- Styling overhaul.
- Long-term dual-path support between Bubble Tea and raw ANSI loop.

## Chosen Approach
Incremental migration to Bubble Tea with callback parity.

The first migration pass replaces only terminal event/render orchestration. Existing `StatusSnapshot` and `Execute` callbacks remain unchanged and continue to define behavior for `run` and `shell` modes. After parity is verified, remove the legacy raw-input/ANSI redraw path.

## Architecture
- Keep domain/control logic unchanged and callback-driven.
- Introduce a Bubble Tea model in `cmd/throwntom` that owns:
  - prompt input buffer
  - latest status line
  - morning reminder pending flag
  - message line
- Implement Bubble Tea `Update` as the single event reducer for:
  - key input
  - periodic tick
  - resize events
- Implement Bubble Tea `View` to render the same 3-line contract.
- Add a thin adapter from existing mode entrypoints (`run`, `shell`) into the Bubble Tea model.
- Remove manual raw mode and ANSI cursor anchoring after parity is proven.

## Data Flow
1. Mode startup:
   - validate TTY preconditions
   - construct existing `StatusSnapshot` and `Execute` callbacks
   - initialize Bubble Tea model with initial snapshot and empty prompt
2. Event processing:
   - tick message every second: refresh status via `StatusSnapshot`
   - key message:
     - printable/backspace update prompt
     - enter submits prompt using `Execute`, clears input, updates state from response
     - ctrl-c exits without command execution
   - window-size message triggers framework-managed redraw behavior
3. Exit:
   - `quit`/`exit` responses trigger Bubble Tea quit command and normal program return

## Error Handling
- Missing callback functions are startup errors and fail fast.
- Command execution errors are non-fatal:
  - render error text on the `message:` line
  - continue interactive loop
- Snapshot callback contract remains unchanged in this migration (`(string, bool)`), so no snapshot error branch is added yet.
- Unrecoverable startup/runtime errors return contextual errors to mode entrypoints.
- Preserve existing daemon command semantics for:
  - `start`, `new-cycle`, `pause`, `resume`, `stop`, `confirm`, `snooze`, `skip-today`, `status`, `test-sound`, `quit`, `exit`

## Testing Strategy (Test Pyramid + Red/Green)
Unit tests (primary):
- Bubble Tea model update behavior for printable/backspace/enter/ctrl-c.
- Tick-driven refresh behavior.
- Resize handling preserves prompt input state.
- View output invariants for the 3-line contract.

Integration tests (secondary):
- Deterministic loop/callback tests for tick + typing + submit behavior.
- Error rendering behavior (`message:` line updates without loop exit).

End-to-end tests (minimal):
- Add a focused e2e smoke test to the existing `e2e` suite for typing + periodic refresh + resize, asserting no line-clobber or upward-scroll regression.

Migration impact:
- Rework tests tightly coupled to raw ANSI internals.
- Keep non-UI domain tests unchanged.

TDD sequence:
1. RED: add failing model/integration/e2e regression tests.
2. GREEN: implement minimal Bubble Tea adapter/model changes.
3. REFACTOR: remove legacy raw ANSI path after parity is verified.

Verification command:
- `go test -timeout 30s ./...`

## Risks and Mitigations
- Risk: behavior drift during UI runtime swap.
  - Mitigation: preserve callback contracts and command semantics unchanged.
- Risk: incomplete regression coverage during migration.
  - Mitigation: add explicit e2e smoke test for resize-related regression class.
- Risk: dependency creep.
  - Mitigation: constrain new dependency usage to terminal UI package boundaries only.
