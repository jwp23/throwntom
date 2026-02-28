# throwntom

CLI-first throwntom daemon with repeating sound reminders until explicit confirmation.

## Build

```bash
go build -o throwntom ./cmd/throwntom
```

## Install

```bash
go install ./cmd/throwntom
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
go build ./cmd/throwntom
```

## Notes

- On macOS, notifier uses `afplay` with system sound `Glass.aiff`.
- On Linux, notifier first tries `sound_command` (if configured), then `paplay`, `canberra-gtk-play`, `aplay`, and finally terminal bell (`\a`).
- `sound_command` is optional and must be a TOML string array where the first item is the executable, and remaining items are args.
