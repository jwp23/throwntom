# Urgtomat Cycle, TOML, and Countdown Design (v1.1)

## Goal
Extend urgtomat to support standard multi-session Pomodoro cadence, TOML configuration, and a live terminal countdown.

## Approved Behavior
- Default cycle:
  - Work: 25 minutes
  - Short break: 5 minutes
  - Long break: 15 minutes
  - Long break frequency: every 4 completed work sessions
- Cycle values are configurable in config only (single source of truth).
- Track completed work sessions for the current work day.
- Reset daily completed count on the first `start` command of that day.
- Show live terminal countdown in `MM:SS`.
- Use single-line terminal refresh for countdown updates.
- During transition wait-for-confirm, show `transition pending` instead of decrementing.
- CLI help/usage should display long flags with double dashes (for example `--config`).

## Configuration Format
- Replace JSON with TOML as the primary format.
- Use a constrained TOML subset (stdlib-only parser implementation):
  - scalar keys (`key = value`)
  - string arrays for weekdays
  - no nested tables required for v1.1
- Example config shape:
  - `work_minutes = 25`
  - `short_break_minutes = 5`
  - `long_break_minutes = 15`
  - `long_break_every = 4`
  - `repeat_secs = 20`
  - `schedule_time = "09:15"`
  - `schedule_days = ["Mon","Tue","Wed","Thu","Fri"]`

## Architecture Changes
### 1) Engine
- Add explicit break types: `ShortBreak` and `LongBreak`.
- Add counters:
  - `workSessionsInBlock`
  - `completedToday`
  - `workDayStarted`
- Transition logic:
  - completed work -> awaiting confirm
  - confirm next:
    - every `long_break_every` work sessions -> long break
    - otherwise -> short break
  - confirm from any break -> work

### 2) App Runtime
- Track `phaseEndAt` for active period.
- Add countdown renderer tick every second.
- Render includes:
  - phase
  - remaining `MM:SS`
  - today completed count
  - current work-session index in block (for example `2/4`)
- Keep reminder loop and confirmation flow unchanged conceptually.

### 3) Config
- Replace JSON load path with TOML file load path.
- Keep defaults and validation strict:
  - durations > 0
  - `long_break_every > 0`
  - valid schedule time
  - non-empty weekday list

### 4) CLI
- Keep stdlib `flag`.
- Help text and examples should show `--config`.
- Startup banner should print active cycle settings so user sees source-of-truth values.

## Error Handling
- Invalid TOML or unknown key format: fail fast with contextual error.
- Missing file with `--config`: fail with explicit path error.
- Countdown renderer failures should not crash daemon; degrade to periodic line prints.

## Testing Focus
- Engine:
  - short vs long break selection cadence
  - daily counter increment/reset semantics
- Config:
  - TOML parsing success paths
  - invalid duration/time/day formats
- App:
  - countdown format and pending-state rendering
  - status includes completed-today/session-progress indicators

## Risks and Mitigations
- Risk: custom TOML parser complexity.
  - Mitigation: intentionally constrained TOML subset and explicit documentation.
- Risk: countdown output noise in terminals.
  - Mitigation: single-line refresh and only one renderer goroutine.
- Risk: ambiguous "new work day" boundary.
  - Mitigation: explicit reset rule on first `start`.
