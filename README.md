# throwntom

thrown tomatos => throwntom

CLI-first pomodoro timer that won't let you forget to start timers, with repeating reminders until explicit confirmation.

## Build

```bash
go build -o throwntom ./cmd/throwntom
```

## Install

```bash
go install github.com/jwp23/throwntom/cmd/throwntom@latest
```

## Modes

`throwntom` now supports both local interactive use and background daemon use.

### Local interactive (default)

```bash
throwntom
```

Equivalent explicit mode:

```bash
throwntom run
```

### Background daemon

```bash
throwntom daemon
```

Daemon control from CLI:

```bash
throwntom ctl status
throwntom ctl start
throwntom ctl "snooze 10m"
```

Interactive shell connected to daemon:

```bash
throwntom shell
```

With config file:

```bash
throwntom --config ./throwntom.toml daemon
```

## Daemon Commands

Type these commands in `throwntom shell` or pass them through `throwntom ctl ...`:

- `start` - start work period
- `pause` - pause the active pomodoro or break timer
- `resume` - resume a paused pomodoro or break timer
- `stop` - stop active timer and return to idle
- `confirm` - acknowledge transition and start next phase
- `snooze <duration>` - snooze current reminder (example: `snooze 10m`)
- `skip-today` - stop reminders for the current day
- `status` - print current status
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

## Service setup (Linux and macOS)

Templates are included for:

- `packaging/systemd/throwntom.service`
- `packaging/launchd/io.github.jwp23.throwntom.plist`

Installer script:

```bash
./packaging/install-service.sh
```

Environment overrides supported by the installer:

- `BINARY_PATH`
- `CONFIG_PATH`
- `SOCKET_PATH`
- `LOG_OUT_PATH` (macOS launchd)
- `LOG_ERR_PATH` (macOS launchd)

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
- Default daemon socket path is `$XDG_RUNTIME_DIR/throwntom.sock` when available, otherwise `/tmp/throwntom.sock`.
