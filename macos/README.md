# Throwntom for macOS

macOS client for `throwntomd`: one phase-coloured window, reached with ⌘-Tab or the Dock. All timer and task logic stays in the Go
daemon; the app renders `DaemonState` and sends commands over the Unix socket at
`~/.config/throwntom/daemon.sock`. Design: `docs/designs/native-macos-client.md`.

## Requirements

Building the app — whether to install it or to develop on it — needs:

- macOS 14 or later to run it (built and tested on macOS 26).
- Xcode 26 with its command-line tools: `build.sh` uses `swift build` and the
  macOS SDK from it, and CI runs the tests with `xcodebuild`. There is no
  prebuilt download.
- Go (version in `go.mod`) to build the embedded `throwntomd`.

## Install

    macos/install.sh [dir]   # ~1 min: quit the app, stop its agent, build, copy to ~/Applications (or dir), open

The bundle lands where Spotlight and Launchpad find it. Rebuilding after a
change is the same command; it does the reload described under Development
loop for you.

## Build only

    macos/build.sh [dir]     # → macos/.build/Throwntom.app (or dir); does not open it
    open macos/.build/Throwntom.app

A release build takes about a minute the first time and well under that
afterwards.

## First launch

On first launch the app writes a launchd agent
(`~/Library/LaunchAgents/com.jwp23.throwntom.daemon.plist`) naming the
`throwntomd` inside its own bundle, and loads it; launchd starts the daemon and
keeps it alive. Until the socket answers — up to about half a minute after
registration — the window shows "Starting timer…" with the disconnected mascot.

The agent names an absolute path rather than being registered through
SMAppService, which is what makes an upgrade work: a registered agent is pinned
to the designated requirement of the signature it was registered with, and an
ad-hoc build's requirement is its cdhash, so a rebuilt daemon failed the launch
constraint and never started again (`docs/adr/012-the-daemon-runs-from-a-plain-launch-agent.md`).

The window is phase-coloured throughout, so its ground follows the current
phase as it changes. When a reminder is outstanding — a phase awaiting
confirmation, or the morning nudge — the app also posts a notification (it
asks for permission the first time) and bounces the Dock icon. The daemon
plays no sound of its own, and neither does the banner: the app chimes once for
each changed nonzero ring count it observes, the first included, until the
reminder is answered — a missed gap between reads coalesces into a single
chime rather than replaying. Setting `float_window_when_waiting = true` in `config.toml` also keeps
the window above other applications' windows for as long as the reminder is
unanswered, dropping it back on confirm or snooze; it is off by default and
never takes keyboard focus (see the root README for the setting)
(`docs/adr/003-clients-own-user-facing-notification.md`,
`docs/adr/007-the-daemon-plays-no-sound.md`,
`docs/adr/009-the-chime-is-the-only-audio-path.md`).

A pause the user walks away from bounces the Dock too. The daemon keeps that
clock — `paused_too_long_minutes`, ten by default — and publishes
`paused_too_long`; the app asks for attention when it turns true and calls the
bounce off when the timer is resumed, so a resume from the terminal ends it
without the app ever being looked at
(`docs/adr/003-clients-own-user-facing-notification.md`). Setting
`bounce_dock_when_paused = false` in `config.toml` turns the bounce off; the
daemon keeps publishing `paused_too_long` on the same clock either way, the
app just declines to act on it (see the root README for the setting).

The app never spawns the daemon itself. If the socket is unreachable it
reconnects with backoff and, after three failures, re-registers the agent.

Press ⌘/ for the keyboard shortcut sheet (Esc or Done closes it); it lists
every shortcut currently bound, generated from the same menu models the
app's menus use, so it can't drift out of sync.

If launchd has no job for the agent (after a `bootout`), or its plist names the
bundle an upgrade replaced, the app rewrites and reloads it after three failed
connection attempts; the window's header shows "Starting timer…" meanwhile.
If launchd refuses outright the header reads "Timer service can't launch" and the
note under it names launchd and points at the **Start Timer Service** chip, which
retries the registration.

## Tests

    cd macos/Throwntom && swift test

## Style

    macos/swift-lint.sh          # lint: Airbnb SwiftFormat config + SwiftLint rules
    macos/swift-lint.sh --fix    # autocorrect, then report what it could not fix

The configs in `Throwntom/.swiftformat` and `Throwntom/.swiftlint.yml` are copied
verbatim from [airbnb/swift](https://github.com/airbnb/swift) at the newest revision
the pinned SwiftFormat release understands. `brew install swiftformat swiftlint` gets
you close, but a brew upgrade can drift past the pin; when the installed version
doesn't match, `swift-lint.sh` downloads the pinned release itself, verifies it
against the checksum `ci.yml` uses, and caches it under `macos/.swift-lint-cache`
(gitignored) so that only happens once per checkout (each worktree has its
own cache).

`DaemonClient` and the transport are tested against a real `throwntomd`,
built by the tests with `go build` and run with `HOME` under `/tmp`.

## Development loop

- After `macos/build.sh`, launchd refuses the re-signed daemon (it pins the
  agent's code signature at registration; `kickstart -k` fails with
  `OS_REASON_CODESIGNING`). Reload it: quit the app,
  `launchctl bootout gui/$(id -u)/com.jwp23.throwntom.daemon`, then reopen the
  app — it re-registers the new binary. Budget a minute for the rebuild and up
  to half a minute of "Starting timer…" after reopening — the client's reconnect
  backoff, tracked as bead `throwntom-mwh` in the project's issue tracker.
  `macos/install.sh` runs this whole loop.
- To develop without the app: `macos/agent.sh install` runs
  `macos/.build/throwntomd` under a separate label (`com.jwp23.throwntom.dev`)
  logging to `~/.config/throwntom/daemon.log`; `restart` reloads it after a
  rebuild; `uninstall` removes it.
- Only one daemon can hold `~/.config/throwntom/daemon.lock`. Uninstall the
  dev agent before running the app, and quit the TUI: the TUI and the daemon
  share the session file.
- `tools/tomctl state` / `tools/tomctl events` show what the app sees;
  `docs/development.md` covers driving phases, touring every mascot pose,
  and screenshotting the window from a script.

## Stopping

Quitting the app leaves the daemon running under launchd (`KeepAlive`), so the
timer and its end-of-phase reminder continue. That is deliberate: the daemon
exists to keep you on track when you forget the app
(`docs/adr/006-daemon-lifecycle-and-config-reload.md`). There are two ways to
make it stop, and they mean different things.

- **Done for Today** — a chip in the window and an item in the Timer menu,
  offered whatever the timer is doing. Ends the work day: the phase stops and
  nothing reminds you again until tomorrow. The window then reads "Done for
  today" rather than "Idle", and it survives a daemon restart.
- **Stop Timer Service** — the chip under the timer verbs, and the group below
  the divider in the Timer menu. Unregisters the `launchd` agent and stops the
  daemon, so nothing is timing at all; the window turns dark and offers **Start
  Timer Service**. Use it when you want the machine quiet, not just the day
  over.

  The stop holds for as long as the app stays open. It is **not** yet persisted:
  the next launch of the app dials, fails three times, and re-registers the
  agent, so a stopped service comes back when you next open Throwntom (or at
  login, if Launch at Login is on). Whether it should survive a restart is an
  open question — bead `throwntom-faa`. Until that is settled, quit the app to
  keep the service down.

A single phase can still be stopped without ending the day with
`tools/tomctl cmd stop`. `launchctl bootout gui/$(id -u)/com.jwp23.throwntom.daemon`
does what Stop Timer Service does; note that an app which has not been told to
stop re-registers the agent after three failed connections, so quit it first if
you boot the agent out by hand.

## Layout

- `Throwntom/` — Swift package: `ThrowntomClient` (transport, `DaemonClient`,
  `DaemonState`, actions, the reminder notification), `ThrowntomUI` (scenes,
  views, the menu model and the reminder responder), and a thin executable,
  `Throwntom`, which only calls `ThrowntomApp.main()`. Logic lives in the
  libraries so `swift test --enable-code-coverage` reaches it; an executable
  target is never linked into the test bundle. See
  `docs/adr/003-clients-own-user-facing-notification.md` for why the app
  posts its own reminder notification instead of shelling out to a helper.
- `bundle/` — `Info.plist` and the launchd agent plist copied into the app.
- `build.sh`, `install.sh`, `agent.sh` — build, install-and-open, and dev-agent scripts.
- `swift-lint.sh` — Airbnb style check used by pre-commit and CI.
