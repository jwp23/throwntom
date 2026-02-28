# throwntom

thrown tomatos => throwntom

CLI-first pomodoro timer that won't let you forget to start the timers! with repeating sound reminders until explicit confirmation.

## Build

```bash
go build -o throwntom ./cmd/throwntom
```

## Install

```bash
go install github.com/jwp23/throwntom/cmd/throwntom@latest
```

## Run

Default config:

```bash
./throwntom
```

With config file:

```bash
./throwntom --config ./throwntom.toml
```

## Daemon Commands

Type these commands in the daemon prompt:

- `start` - start work period
- `pause` - pause the active pomodoro or break timer
- `resume` - resume a paused pomodoro or break timer
- `stop` - stop active timer and return to idle
- `confirm` - acknowledge transition and start next phase
- `snooze <duration>` - snooze current reminder (example: `snooze 10m`)
- `skip-today` - stop reminders for the current day
- `test-sound` - play the reminder sound immediately to verify terminal audio/bell
- `quit` - stop daemon
- `exit` - alias for `quit`

## Config

Example `throwntom.toml`:

```toml
work_minutes = 25
short_break_minutes = 5
long_break_minutes = 15
long_break_every = 4
repeat_secs = 20
schedule_time = "09:15"
schedule_days = ["Mon", "Tue", "Wed", "Thu", "Fri"]
sound_command = ["paplay", "/usr/share/sounds/freedesktop/stereo/bell.oga"]
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
