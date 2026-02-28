# urgtomat

CLI-first urgtomat daemon with repeating sound reminders until explicit confirmation.

## Build

```bash
go build -o urgtomat ./cmd/urgtomat
```

## Run

Default config:

```bash
./urgtomat
```

With config file:

```bash
./urgtomat --config ./urgtomat.toml
```

## Daemon Commands

Type these commands in the daemon prompt:

- `start` - start work period
- `confirm` - acknowledge transition and start next phase
- `snooze <duration>` - snooze current reminder (example: `snooze 10m`)
- `skip-today` - stop reminders for the current day
- `status` - print current cycle state and morning reminder status
- `quit` - stop daemon

## Config

Example `urgtomat.toml`:

```toml
work_minutes = 25
short_break_minutes = 5
long_break_minutes = 15
long_break_every = 4
repeat_secs = 20
schedule_time = "09:15"
schedule_days = ["Mon", "Tue", "Wed", "Thu", "Fri"]
```

## Verify

```bash
go test ./... -v
go build ./cmd/urgtomat
```

## Notes

- v1 notifier uses macOS `afplay`.
- Linux support can be added by implementing another notifier adapter behind the `internal/notifier` interface.
