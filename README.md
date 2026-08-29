<p align="center">
  <img src="docs/images/throwntom.png" alt="throwntom" width="200">
</p>

# throwntom

thrown tomatos => throwntom

Pomodoro timer that won't let you forget to start timers, with repeating reminders until explicit confirmation.

## Interfaces

throwntom is three programs that share one timer engine and one config:

- **`throwntom`** — the original terminal UI. It runs the timer in-process and
  does not use the daemon yet (that move is planned; see the Daemon section).
- **`throwntomd`** — the background daemon: runs the timer, reminders and task
  store and serves a JSON API on a Unix socket. Every graphical client is a
  thin view over it.
- **Throwntom.app** — the macOS window app, backed by `throwntomd`.

Native Linux and Android clients are next. Once they exist the TUI is the odd
one out — its own test surface for a timer the daemon already runs — so expect
it to become a daemon client or be retired; it stays for now because some
people simply prefer a terminal.

Prerequisites: Go (version in `go.mod`) for the TUI and daemon; the macOS app
additionally needs Xcode 26 with its command-line tools (`swift build` and the
SDK come from it — see `macos/README.md`).

## Terminal UI

Build or install the TUI:

```bash
go build -o throwntom ./cmd/throwntom
go install github.com/jwp23/throwntom/v3/cmd/throwntom@latest
```

Run it:

```bash
throwntom
throwntom --config path/to/config.toml
```

Build the daemon the same way (`go build -o throwntomd ./cmd/throwntomd`); on
macOS the app bundle carries its own copy, so you only need this to run the
daemon by hand.

## macOS app

The macOS client is one phase-coloured window with the tomato mascot on top: it
draws what `throwntomd` reports and sends the timer verbs back.

```bash
macos/install.sh        # build, install to ~/Applications, and open
```

That takes about a minute. The first launch registers the bundled launchd agent
that runs `throwntomd` — the window shows "Starting timer…" for up to half a
minute while it comes up — and after that the app is in Spotlight and Launchpad,
and Launch at Login is a toggle in its application menu. Phase changes post a
notification and bounce the Dock icon as well as recolouring the window; press
⌘/ in the window for every shortcut.

Quitting the app does not stop the timer: the daemon keeps running (and keeps
reminding you) under launchd. The window has no stop button yet: **Skip Today**
(shown while idle) ends the day, and a running or owed phase is stopped from a
terminal with `tools/tomctl cmd stop`. To stop the daemon itself, quit the app
first — an open app re-registers the agent after a few failed connections —
then:

```bash
launchctl bootout gui/$(id -u)/com.jwp23.throwntom.daemon
```

The app registers it again the next time it opens. Rebuilding is the same
`macos/install.sh`; details and the daemon-only dev loop are in
`macos/README.md`, and driving the daemon or checking the window from a
terminal is in `docs/development.md`.

## Commands

The TUI reads these at its prompt; the daemon accepts the same lines through
`tools/tomctl cmd <line>`, except that `start` and `confirm` prompt for task
focus and so fail non-interactively — use the daemon's `/v1/timer/start` and
`/v1/timer/confirm` routes for those (see `docs/development.md`). The macOS
window exposes the timer verbs as buttons and menu items and the task commands
through its tasks panel.

- `start` - start work period
- `new-cycle` - start a fresh cycle now (reset cycle progress, keep today's total)
- `pause` - pause the active pomodoro or break timer
- `resume` - resume a paused pomodoro or break timer
- `stop` - stop active timer and return to idle (forgets the owed phase and clears focused tasks)
- `confirm` - acknowledge transition and start next phase now
- `snooze <duration>` - keep the owed phase and focused tasks, ask again later (example: `snooze 10m`)
- `skip-today` - stop reminders for the current day
- `stats` - show productivity dashboard (today, week, month, all-time, streaks, patterns)
- `status` - print current status
- `test-sound` - play the reminder sound immediately to verify terminal audio/bell
- `quit` - exit throwntom
- `exit` - alias for `quit`

`snooze` works whenever a reminder is ringing, not just in the morning — including
while waiting for `confirm` at the end of a pomodoro or break. It is the only one
of `confirm`, `snooze`, `stop` and `skip-today` that doesn't lose anything: it just
asks again later. `stop` and `skip-today` both drop the phase you were owed;
`stop` also clears focused tasks.

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

### A phase counts through downtime

A pomodoro is wall-clock time, so a running phase keeps counting while nothing
is running: the session stores an absolute end time, not a remaining duration.
Restarting the daemon ten minutes into a 25-minute pomodoro leaves 15 minutes,
not 25, and a phase whose end time passed while the daemon was down comes back
already complete and awaiting confirmation. This is deliberate — see
[ADR-006](docs/adr/006-daemon-lifecycle-and-config-reload.md). Stopping the
timer service is therefore not a way to pause: use `pause`, which stores the
remaining duration instead.

## Productivity Analytics

throwntom records every meaningful event (pomodoro start/complete, breaks, pauses, snoozes) to `~/.config/throwntom/events.jsonl`. This append-only log powers the `stats` command, which displays:

- **Today / This Week / This Month / All Time** — pomodoro counts, focus time, pauses, snoozes
- **Streaks** — current and longest consecutive days with at least one pomodoro
- **Patterns** — best day of the week, most productive hour, snooze/pause rates

Pomodoro counts carry a tier glyph and color (thresholds configurable):

| Tier | Default range | Glyph | Color |
|------|--------------|-------|-------|
| Cool | 0–2 | ○ | gray |
| Warm | 3–5 | ◐ | tomato |
| Hot | 6+ | ● | teal |

## Daemon (`throwntomd`)

`throwntomd` runs the timer, reminders and task store as a background
process and serves a JSON API over `~/.config/throwntom/daemon.sock`
(see `docs/designs/native-macos-client.md` for the routes). Only one
instance runs at a time (`daemon.lock`). The TUI does not talk to the daemon
yet — it runs its own copy of the engine — so do not run both at the same
time: they share `session.json`.

Control the daemon from the command line with `tools/tomctl` (see
`tools/tomctl/README.md` for usage and build instructions, and
`docs/development.md` for driving phases and stopping the daemon). The state
document's `paused_from` field names the phase a pause interrupted, so a
client can keep showing that phase while paused.

## Config

Config file location: `~/.config/throwntom/config.toml`

The first time `throwntomd` starts without one, it writes a fully documented
`config.toml` there: every setting, with its default, commented out. Edit the
file in place — uncomment a line and change it. An existing config is never
overwritten. The macOS app opens this file with **Open Config File…** (⌘,).

Example `config.toml`:

```toml
[pomodoro]
work_minutes = 25
short_break_minutes = 5
long_break_minutes = 15
long_break_every = 4

# days omitted → defaults to weekday (Mon-Fri)
[[schedule]]
time = "09:15"

# specific-day override carves out from the default group
[[schedule]]
days = ["Fri"]
time = "10:00"

repeat_secs = 20
repeat_limit_secs = 300
sound_command = ["paplay", "/usr/share/sounds/freedesktop/stereo/bell.oga"]
morning_reminder_pending = true
emoji = true

[stats]
tier_low = 2
tier_mid = 5
```

`repeat_limit_secs` bounds how long an unanswered reminder keeps alerting, so a
reminder nobody is around to acknowledge stops on its own rather than ringing
until the daemon is stopped.

### `sound_command`

`sound_command` is an optional TOML string array: the first item is the
executable, the rest are its arguments. Setting it changes how throwntom
makes noise:

- **On macOS**, it *replaces* the built-in sound entirely — throwntom runs
  your command instead of `afplay`, for every sound (morning nudge, confirm
  reminder, `test-sound`) with no way to tell them apart by ear.
- **On Linux**, it is tried first and, if it fails, throwntom falls back to
  `paplay`, `canberra-gtk-play`, `aplay`, then the terminal bell.

On macOS, to pick a different system sound (the built-in choice is Blow for
the morning nudge, Glass for confirm reminders, Tink for `test-sound`):

```toml
sound_command = ["afplay", "/System/Library/Sounds/Purr.aiff"]
```

To silence sound entirely (e.g. while testing or in a meeting), set:

```toml
sound_command = ["true"]
```

`/usr/bin/true` exits 0 immediately and prints nothing, so throwntom reports
success with no audio.

### Reloading

`throwntomd` watches `config.toml` and applies edits within a few seconds,
with no restart. It polls every two seconds and waits for an edit to stop
changing before applying it, so a save lands on the second poll that sees it. The pomodoro already running is re-derived from the
new durations: it keeps the time it has spent and runs for whatever the new
duration leaves. Shortening a duration below the time the current phase has
already spent ends that phase immediately — the edit says the phase should
already be over. A file that does not parse is reported on the daemon's
stderr and ignored; the config in force stays in force.

Reloading covers `[pomodoro]`, `[[schedule]]`, `repeat_secs` and
`repeat_limit_secs`. The rest needs a restart of whichever process reads it:

- `sound_command` — the daemon builds its notifier once, at startup.
- `morning_reminder_pending` — it answers whether today's morning reminder is
  owed when the daemon starts, a question already settled by the time an edit
  arrives.
- `emoji` and the `[stats]` tiers — client settings, read by `throwntom` when
  it launches.

An edit made while the daemon is *stopped* is a different case: the phase that
was in flight comes back with the end time it already had (see [A phase counts
through downtime](#a-phase-counts-through-downtime)), so a duration changed
during the outage applies to the next phase, not the one that was running.
Editing the same value with the daemon up re-derives the running phase
immediately. Which of the two should win is still open — tracked on
`throwntom-3tu`.

If you only need to silence *one* running reminder rather than sound in
general (for example, ducking out of a meeting), don't edit the config —
run `tools/tomctl cmd snooze 10m` or `tools/tomctl cmd stop` against the
running daemon instead.

Schedule supports day aliases: `"weekday"` expands to Mon-Fri, `"weekend"` to Sat-Sun. Specific-day entries automatically carve out from alias expansions.

## Project Layout

- `cmd/throwntom/` — main binary: CLI entry point, Bubble Tea model, rendering
- `cmd/throwntomd/` — daemon binary: background process serving the JSON API
- `internal/analytics/` — productivity dashboard computation
- `internal/config/` — TOML config parsing
- `internal/core/` — timer/task/reminder orchestration shared by the TUI and daemon
- `internal/daemon/` — daemon HTTP API, socket lifecycle and shutdown
- `internal/engine/` — pomodoro state machine
- `internal/eventlog/` — append-only event log
- `internal/notifier/` — desktop notifications and sound
- `internal/pomodoro/` — the pomodoro timer: the engine with a wall clock on it
- `internal/reminder/` — reminder scheduling
- `internal/scheduler/` — work schedule (days/times)
- `internal/session/` — session persistence
- `internal/task/` — task store
- `tools/tomctl/` — command-line client for the daemon API
- `tools/icon-colors.sh` — dominant colours of the app icon as hex (ImageMagick); keeps `DESIGN.md`'s `icon-*` tokens traceable
- `tools/sonar-audit.sh` — reports SonarCloud issues/hotspots on a branch; CI runs it on main to flag drift
- `tools/dev-quiet.sh` — runs throwntom against an isolated, silent config for manual testing (see [Dev tools](#dev-tools))
- `tools/mascot-snap.sh` — renders every mascot pose offscreen to PNGs (see `docs/development.md`)
- `tools/app-capture.sh` — screenshots the app window by window number, no Accessibility permission needed
- `macos/Throwntom/` — Swift package: the macOS window app and daemon client
- `macos/build.sh` — builds `Throwntom.app` with `throwntomd` embedded (see `macos/README.md`)
- `macos/install.sh` — the dev loop: quit, stop the agent, build, install to `~/Applications`, open
- `docs/development.md` — driving the daemon and checking the app from a terminal
- `e2e/` — end-to-end tests (build tag: `e2e`)
- `integration/` — integration tests (build tag: `integration`)

## Verify

```bash
go test -timeout 30s ./... -v
go vet ./...
go build ./cmd/throwntom ./cmd/throwntomd   # TUI and daemon
cd macos/Throwntom && swift test            # macOS app (needs Xcode)
```

## Pre-commit checks

Install local git hooks:

```bash
./scripts/install-git-hooks.sh
```

Commit-time checks in `.githooks/pre-commit` run:

- `gofmt` verification (`gofmt -l .`)
- Airbnb Swift style when Swift files are staged (`macos/swift-lint.sh`; `--fix` to autocorrect)
- fast tests (`go test -timeout 30s ./...`)

Heavier checks intentionally kept out of pre-commit and run in CI:

- lint + complexity gate (`golangci-lint run ./...`)
- integration tests (`go test -timeout 30s -tags=integration ./integration`)
- e2e tests (`go test -timeout 30s -tags=e2e ./e2e`)
- security scan (`govulncheck`)

## Dev tools

```bash
tools/dev-quiet.sh [throwntom args...]
```

Runs `throwntom` with `HOME` pointed at a throwaway directory (cleaned up on
exit) and a `config.toml` there setting `sound_command = ["true"]`. It
neither plays sound nor reads or writes your real `~/.config/throwntom`, so
it's safe to use while working or in a meeting without disturbing a real
session. Extra arguments (e.g. `--config`) are forwarded to `throwntom`.

## Notes

- On macOS, notifier uses `afplay` with a system sound chosen by name
  (`morning`→Blow, `default`→Glass, `test`→Tink), unless `sound_command` is
  set, in which case that command replaces `afplay` for all of them.
- On Linux, notifier first tries `sound_command` (if configured), then `paplay`, `canberra-gtk-play`, `aplay`, and finally terminal bell (`\a`).
- `sound_command` is optional and must be a TOML string array where the first item is the executable, and remaining items are args. See [Config](#config) for the silent-testing recipe.
