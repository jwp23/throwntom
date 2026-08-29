# Throwntom for macOS

macOS client for `throwntomd`: one phase-coloured window, reached with ⌘-Tab or the Dock. All timer and task logic stays in the Go
daemon; the app renders `DaemonState` and sends commands over the Unix socket at
`~/.config/throwntom/daemon.sock`. Design: `docs/designs/native-macos-client.md`.

## Requirements

- macOS 14+, Xcode 26 (`xcodebuild` and the Swift 6 toolchain), Go (see `go.mod`).

## Build and run

    macos/install.sh        # quit, stop the agent, build, copy to ~/Applications, open
    macos/build.sh          # build only → macos/.build/Throwntom.app
    open macos/.build/Throwntom.app

`install.sh` puts the bundle where Spotlight and Launchpad find it and runs the
reload below for you; pass another directory to install elsewhere.

On first launch the app registers its bundled launchd agent
(`com.jwp23.throwntom.daemon`), which starts `throwntomd` and keeps it alive.
macOS shows a "Background item added" notification; nothing to approve. The
agent appears in System Settings → General → Login Items.

The app never spawns the daemon itself. If the socket is unreachable it
reconnects with backoff and, after three failures, re-registers the agent.

Press ⌘/ for the keyboard shortcut sheet (Esc or Done closes it); it lists
every shortcut currently bound, generated from the same menu models the
app's menus use, so it can't drift out of sync.

If the agent is enabled in Login Items but launchd has no job for it (after a
`bootout`, or a rebuild), the app unregisters and re-registers it after three
failed connection attempts; the window's header shows "Starting timer…" meanwhile.

## Tests

    cd macos/Throwntom && swift test

## Style

    macos/swift-lint.sh          # lint: Airbnb SwiftFormat config + SwiftLint rules
    macos/swift-lint.sh --fix    # autocorrect, then report what it could not fix

The configs in `Throwntom/.swiftformat` and `Throwntom/.swiftlint.yml` are copied
verbatim from [airbnb/swift](https://github.com/airbnb/swift) at the newest revision
the pinned SwiftFormat release understands; the script refuses to run under any other
tool version so a developer machine and CI cannot disagree. `brew install swiftformat
swiftlint` provides both.

`DaemonClient` and the transport are tested against a real `throwntomd`,
built by the tests with `go build` and run with `HOME` under `/tmp`.

## Development loop

- After `macos/build.sh`, launchd refuses the re-signed daemon (it pins the
  agent's code signature at registration; `kickstart -k` fails with
  `OS_REASON_CODESIGNING`). Reload it: quit the app,
  `launchctl bootout gui/$(id -u)/com.jwp23.throwntom.daemon`, then reopen the
  app — it re-registers the new binary.
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
timer and its end-of-phase reminder continue. **Stop** in the window idles the
timer and **Skip Today** ends the day; to stop the daemon itself run
`launchctl bootout gui/$(id -u)/com.jwp23.throwntom.daemon` — the app
registers it again on its next launch.

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
