# throwntom

thrown tomatos => throwntom

CLI-first pomodoro timer that won't let you forget to start timers, with repeating reminders until explicit confirmation.

## Build

```bash
go build -o throwntom ./cmd/throwntom
```

## Install

```bash
go install github.com/jwp23/throwntom/v2/cmd/throwntom@latest
```

## Usage

```bash
throwntom
throwntom --config path/to/config.toml
```

## Commands

Type these commands in the interactive prompt:

- `start` - start work period
- `new-cycle` - start a fresh cycle now (reset cycle progress, keep today's total)
- `pause` - pause the active pomodoro or break timer
- `resume` - resume a paused pomodoro or break timer
- `stop` - stop active timer and return to idle
- `confirm` - acknowledge transition and start next phase
- `snooze <duration>` - snooze current reminder (example: `snooze 10m`)
- `skip-today` - stop reminders for the current day
- `status` - print current status
- `test-sound` - play the reminder sound immediately to verify terminal audio/bell
- `quit` - exit throwntom
- `exit` - alias for `quit`

### Task Commands

Manage focused tasks for your pomodoro sessions. Tasks are persisted to `~/.config/throwntom/tasks.json`.

- `task add <desc>` - add a new task
- `task done <n>` - mark task number `n` as completed
- `task remove <n>` - delete task number `n`
- `task list` - show active tasks
- `task completed` - show completed tasks
- `task clear` - clear completed tasks
- `task focus <n>` - focus on task `n` during a work session
- `task unfocus <n>` - remove focus from task at position `n`
- `task up <n>` - move focused task up in priority
- `task down <n>` - move focused task down in priority

When starting a pomodoro or confirming a transition to work, you'll be prompted to select which tasks to focus on for that session.

## Session Persistence

throwntom automatically saves session state to `~/.config/throwntom/session.json` after every command and on shutdown. When you restart, it restores:

- Timer position (adjusted for wall-clock time elapsed while closed)
- Engine state (work, break, paused, awaiting confirmation)
- Completed pomodoro counts for the day
- Focused task selections

If the saved session is from a different day, it is discarded and throwntom starts fresh. If the timer expired while closed, it transitions to awaiting confirmation. Paused timers remain paused with their remaining duration preserved.

## Config

Config file location: `~/.config/throwntom/config.toml`

Example `config.toml`:

```toml
[pomodoro]
work_minutes = 25
short_break_minutes = 5
long_break_minutes = 15
long_break_every = 4

[schedule]
days = ["Mon", "Tue", "Wed", "Thu", "Fri"]
time = "09:15"

repeat_secs = 20
sound_command = ["paplay", "/usr/share/sounds/freedesktop/stereo/bell.oga"]
morning_reminder_pending = true
emoji = true
```

## Verify

```bash
go test -timeout 30s ./... -v
go vet ./...
go build ./cmd/throwntom
```

## Pre-commit checks

Install local git hooks:

```bash
./scripts/install-git-hooks.sh
```

Commit-time checks in `.githooks/pre-commit` run:

- `gofmt` verification (`gofmt -l .`)
- fast tests (`go test -timeout 30s ./...`)

Heavier checks intentionally kept out of pre-commit and run in CI:

- lint + complexity gate (`golangci-lint run ./...`)
- integration tests (`go test -timeout 30s -tags=integration ./integration`)
- e2e tests (`go test -timeout 30s -tags=e2e ./e2e`)
- security scan (`govulncheck`)

## Notes

- On macOS, notifier uses `afplay` with system sound `Glass.aiff`.
- On Linux, notifier first tries `sound_command` (if configured), then `paplay`, `canberra-gtk-play`, `aplay`, and finally terminal bell (`\a`).
- `sound_command` is optional and must be a TOML string array where the first item is the executable, and remaining items are args.
