# Interactive Status UI Design

Date: 2026-02-28

## Context

Current daemon behavior mixes prompt input and status rendering. Status updates are intentionally enabled in non-interactive conditions, while interactive prompt behavior is line-scanned and not suitable for constant redraw.

This design sets product direction and UI scope:
- interactive terminal mode is the only supported runtime mode
- non-interactive runtime is not a supported use case
- CLI subcommand `daemon` is removed; `urgtomat` starts directly

## Goals

- Keep status line constantly updated at 1-second cadence in interactive mode.
- Preserve reliable command entry while status redraws.
- Keep implementation simple (YAGNI) while creating a clean boundary for future refactors.

## Non-Goals

- Command history or arrow-key navigation.
- Full TUI framework adoption.
- Backward compatibility with old CLI subcommand usage.

## Product Scope Decisions

1. Supported mode is interactive TTY only.
2. Non-interactive mode is removed as a supported path.
3. CLI command shape becomes `urgtomat [--config path]` only.

## Architecture

Introduce a small `terminalUI` boundary with two responsibilities:
1. Render two-line interactive screen.
2. Capture basic line editing input.

Daemon loop remains responsible for:
1. Command parsing and execution.
2. Cycle/reminder/scheduler state management.

This keeps domain logic separate from terminal concerns and supports future replacement of UI layer with minimal impact.

## UI Behavior

TTY mode renders exactly two lines:
1. `status: <cycle.StatusLine()> morning_pending=<bool>`
2. `command> <input buffer>`

Redraw rules:
1. periodic redraw every 1 second
2. immediate redraw on input edit (type/backspace)
3. immediate redraw on command submit and command completion
4. immediate redraw after state-changing commands

Input support in scope:
1. printable characters
2. backspace
3. enter

Out of scope now:
1. history
2. arrow keys

## CLI and Runtime Behavior

- Start daemon directly when running `urgtomat`.
- Reject extra positional arguments with usage error.
- Require both stdin and stdout to be terminals.
- If either side is non-TTY, exit with clear message: `daemon requires an interactive terminal`.

## Error Handling

- If raw terminal input setup fails, print contextual error and exit non-zero.
- Always restore terminal state on exit paths.
- Fail fast on invalid command syntax; keep status UI stable after errors.

## Testing Strategy

Unit tests:
1. renderer formatting for status and command lines
2. input buffer behavior (type/backspace/enter)
3. TTY precondition checks

Integration test:
1. simulate interactive redraw while typing
2. verify input buffer survives 1-second status ticks
3. verify command execution and status refresh

Verification command:
- `go test -timeout 30s ./...`

## Risks and Trade-offs

- Implementing basic interactive line editing adds terminal complexity versus scanner-based input.
- Restricting to interactive TTY removes ad-hoc piping behavior, but aligns with product intent and reduces maintenance paths.
- A thin UI boundary provides refactor headroom without introducing framework dependencies.
