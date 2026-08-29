# Developing throwntom

How to drive the daemon and the macOS app from a terminal — for people, and for an agent that
has to check the UI without a human watching.

## The daemon from the command line

`tools/tomctl` talks to a running `throwntomd` over `~/.config/throwntom/daemon.sock`:

```bash
go build -o ~/bin/tomctl ./tools/tomctl     # or: go run ./tools/tomctl ...
tomctl state                                # the State document (see docs/designs/native-macos-client.md)
tomctl events                               # one State per line as it changes, until Ctrl-C
tomctl cmd pause                            # also: resume, stop, confirm, snooze 10, skip-today, new-cycle
tomctl cmd task add "write tests"
```

`tomctl cmd` runs the same command grammar as the TUI. `start` and `confirm` prompt for task focus in
that grammar and fail non-interactively ("invalid input during task selection"); use the timer routes
the app uses instead — they never prompt:

```bash
curl -s --unix-socket ~/.config/throwntom/daemon.sock -X POST http://d/v1/timer/start
curl -s --unix-socket ~/.config/throwntom/daemon.sock -X POST http://d/v1/timer/confirm
```

`stop` idles the timer; it does not stop the daemon. The daemon runs under launchd with `KeepAlive`,
so quitting the app leaves it — and its end-of-phase reminder — running:

```bash
launchctl bootout gui/$(id -u)/com.jwp23.throwntom.daemon   # stop the app-registered daemon
macos/agent.sh uninstall                                     # stop the standalone dev agent
```

The app registers the daemon again on its next launch.

## Touring the phases quickly

Phases are minutes long at minimum, so a tour of every pose takes a few minutes with:

```toml
[pomodoro]
work_minutes = 1
short_break_minutes = 1
long_break_minutes = 1
long_break_every = 2
```

in `~/.config/throwntom/config.toml`, then a daemon restart (`bootout` above, then open the app). Back
up `session.json`, `events.jsonl` and `tasks.json` from `~/.config/throwntom` first and restore them
after: the tour writes completed pomodoros into today's stats. Remove the `[pomodoro]` block afterwards.

## Seeing the app without a human

- `tools/mascot-snap.sh [dir]` renders every mascot pose, the motion extremes and the timer header
  offscreen through `ImageRenderer` (no window, no permissions) into `docs/designs/mascot-screenshots`
  by default. It is the `MascotSnapshotTests` test with `MASCOT_SNAPSHOT_DIR` set.
- `tools/app-capture.sh [out.png]` captures the live window by window number (via `CGWindowList`), so it
  works without granting Accessibility to the terminal.
- Motion check: capture twice 1–2 s apart and compare the mascot region (`sips --cropOffset … --cropToHeightWidth …`
  then `md5`); it must differ while a phase runs and be identical when paused. Reduce Motion cannot be
  toggled from a script (`defaults write com.apple.universalaccess` is refused); flip it in System
  Settings → Accessibility → Display and repeat the check — nothing should move.
- `tools/dev-quiet.sh` runs the TUI against a throwaway `HOME` with sound disabled.

## The macOS dev loop

`macos/install.sh` quits the app, stops the agent, rebuilds, copies the bundle to `~/Applications`
and opens it. The launch-agent label is shared by every build, so whichever bundle you opened last
owns the registered daemon.
