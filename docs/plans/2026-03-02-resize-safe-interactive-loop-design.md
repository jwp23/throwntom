# Resize-Safe Interactive Loop Design

Date: 2026-03-02

## Summary
Replace scanner-driven command input in interactive modes with a raw-input event loop that owns rendering and line editing, so the 3-line UI remains stable during backspace and terminal resize while preserving 1-second status refresh.

## Goals
- Keep the existing 3-line interactive layout:
  1. `status: ...`
  2. `message: ...`
  3. `command> ...`
- Maintain periodic status refresh at 1-second cadence while the prompt is idle and accepting input.
- Preserve reliable command entry under backspace and terminal resize (`SIGWINCH`).
- Keep scope minimal: printable characters, backspace, enter.
- Use only the standard library.

## Non-Goals
- Command history.
- Arrow-key navigation.
- Third-party TUI framework adoption.
- Behavior changes to daemon command semantics.

## Chosen Approach
Adopt an in-process raw-input loop (Go standard library + `syscall`) and keep current daemon/app command flow unchanged.

Alternative approaches considered:
1. Keep `bufio.Scanner` and patch ANSI cursor sequences further.
   - Rejected: terminal-owned line editing remains incompatible with robust periodic redraw and resize safety.
2. Add a third-party TUI framework.
   - Rejected for now: requires dependency approval and larger architectural jump than needed.

## Architecture
Introduce a small interactive loop layer in `cmd/throwntom` that owns terminal-mode lifecycle, input buffering, and redraw triggers.

Responsibilities:
- Interactive loop:
  - enter/restore raw mode safely
  - read key bytes from stdin
  - maintain command input buffer
  - react to 1-second tick, key events, and resize signals
  - request status snapshots and command execution via callbacks
- Terminal UI renderer:
  - render full 3-line frame from explicit state
  - redraw deterministically from known cursor anchor
- Existing mode orchestration (`runLocalMode`, `runShellMode`):
  - provide mode-specific status and command callbacks
  - preserve control command behavior (`start`, `pause`, `resume`, `stop`, `confirm`, `snooze`, `new-cycle`, `skip-today`, `status`, `test-sound`, `quit`, `exit`)

## Data Flow
1. Mode startup validates TTY and builds mode-specific callbacks.
2. Interactive loop enters raw mode and renders initial frame.
3. Event loop processes:
   - ticker events (1 second): refresh status, redraw frame.
   - key events:
     - printable: append to input buffer, redraw.
     - backspace: delete one rune when available, redraw.
     - enter: submit buffer, clear input buffer, update message/status from response, redraw.
   - resize signals (`SIGWINCH`): redraw current frame.
4. On `quit`/`exit` response, loop exits and restores terminal mode.

## Error Handling
- If raw mode setup fails, print contextual error and exit non-zero.
- Always restore terminal mode with `defer` on every exit path.
- If stdin read fails, report `input error: ...` and exit after restore.
- If command execution fails (for example socket control errors in shell mode), show error on `message:` line and continue loop.
- Resize-trigger handling is best-effort; missed signals are recovered by subsequent tick/redraw.

## Testing Strategy
Test pyramid with Red/Green TDD:

Unit tests (primary):
- input reducer behavior for printable/backspace/enter.
- renderer output preserves 3-line format and deterministic redraw sequence.
- redraw policy handles tick and resize events correctly.

Integration tests (secondary):
- simulate interactive loop with fake input/tick channels.
- verify prompt buffer survives periodic ticks.
- verify prompt remains visible and command submission works after resize-triggered redraw.

End-to-end tests (minimal):
- defer unless required; unit/integration should cover target behavior.

Verification command:
- `go test -timeout 30s ./...`

## Risks and Mitigations
- Risk: terminal mode not restored on panic/early return.
  - Mitigation: single raw-mode entry/exit path with guaranteed deferred restore.
- Risk: race between status updates and command execution output.
  - Mitigation: single loop-owned render state; callbacks update state before redraw.
- Risk: ANSI redraw sequence still assumes wrong cursor position.
  - Mitigation: full-frame redraw from known anchor rather than Scanner-dependent cursor restore.
