# Urgtomat Reminder Design (v1)

## Goal
Build a desktop-first Urgtomat reminder system that reliably prompts the user to:
- start the day’s first urgtomat cycle
- acknowledge every work/break transition
- hear repeated reminders until explicit confirmation

Initial target is macOS. Architecture must keep Linux support straightforward to add.

## User Outcomes
- Morning reminder at a configurable fixed time (default `Mon-Fri 09:15`).
- Optional prompt after first keyboard/mouse activity after login.
- Morning prompt offers: `Start`, `Snooze`, `Skip today`.
- If no activity-based confirmation is set, fixed-time default still triggers.
- Work/break transition reminders repeat until user confirms the next state.

## Non-Goals (v1)
- No GUI/menu bar app in v1.
- No mobile sync.
- No account/user-management features.

## Approach
Use a CLI daemon-style application with a platform adapter layer:
- Fast path to a working product for a CLI-oriented workflow.
- Core logic remains platform-agnostic.
- OS-specific behavior isolated behind interfaces.

## Architecture
### 1) `UrgtomatEngine`
State machine and timing rules:
- States: `Idle`, `Work`, `Break`, `Paused`
- Transitions triggered by confirmation actions and timer completion
- Configurable durations

### 2) `Scheduler`
Determines when reminders should fire:
- Fixed-time schedule (weekday + local time)
- Optional first-activity trigger mode
- Startup catch-up behavior if app was offline during a scheduled event

### 3) `ReminderLoop`
Handles repeated alerts:
- Plays sound at a configurable repeat interval
- Stops only on explicit confirmation (`start`, `next`, `snooze`, `skip`)
- Escalation policy can be extended later (voice, volume ramp, etc.)

### 4) `Notifier` interface
Platform abstraction for reminders:
- `play_sound(sound_id | file_path) -> Result`
- Optional future method: `speak(text, voice)`
- v1 implementation: `macOSNotifier`
- future implementation: `LinuxNotifier`

### 5) `CommandHandler` (CLI)
User control surface:
- `start`, `pause`, `resume`, `status`
- `confirm`, `snooze <duration>`, `skip-today`
- `config set ...`, `config show`

### 6) `ConfigStore`
Local file-backed configuration:
- schedule (`days`, `time`)
- durations (`work`, `break`)
- reminder repeat interval
- activity-trigger enable/disable
- notifier defaults (sound and optional voice for future use)

## Data Model (conceptual)
- `ScheduleRule`: weekdays + local time
- `MorningPromptPolicy`: fixed-time, activity-trigger, fallback behavior
- `CycleConfig`: work and break lengths
- `ReminderPolicy`: repeat interval and retry behavior
- `RuntimeState`: current phase, next due reminder, pending confirmation

## Error Handling
- Invalid config: fail fast with actionable validation errors.
- Notifier failure: fallback to terminal bell + explicit terminal message.
- Missed schedule due to downtime: trigger catch-up reminder on startup.

## Testing Strategy
- Unit tests for state machine transitions and edge cases.
- Unit tests for scheduler date/time evaluation.
- Unit tests for repeat-until-confirm reminder behavior.
- Unit tests for config parsing/validation.
- Contract tests for notifier interface with mocked platform adapters.

## Risks and Mitigations
- Risk: reminders ignored in noisy environment.
  - Mitigation: repeated reminder loop with short interval and mandatory confirmation.
- Risk: cross-platform complexity.
  - Mitigation: strict boundary around OS adapters (`Notifier`, optional activity detector).
- Risk: daemon lifecycle confusion.
  - Mitigation: explicit CLI commands for status and control plus startup catch-up logic.

## Open Decisions for Implementation Planning
- Exact default work/break durations.
- Config file format choice.
- Process model (single long-running daemon vs command-driven background service).
- Precise first-activity detection method per OS.
