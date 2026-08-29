# tomctl

Control a running throwntomd daemon from the command line.

```
tomctl [--socket path] state          # pretty-printed JSON state
tomctl [--socket path] events         # streams one JSON state per line until Ctrl-C
tomctl [--socket path] cmd <line...>  # runs a command line; prints message or error; exit 1 on error
```

Build with `go build ./tools/tomctl`.

Used by integration tests and for driving the daemon without the macOS app.

`cmd start` and `cmd confirm` go through the TUI's command grammar, which prompts for
task focus and fails non-interactively; start or confirm a phase over the timer routes
instead (`curl --unix-socket ~/.config/throwntom/daemon.sock -X POST http://d/v1/timer/start`).
See `docs/development.md`.
