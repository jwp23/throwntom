# Throwntom for macOS

Menu bar client for `throwntomd`. All timer and task logic stays in the Go
daemon; the app renders `DaemonState` and sends commands over the Unix socket at
`~/.config/throwntom/daemon.sock`. Design: `docs/designs/native-macos-client.md`.

## Requirements

- macOS 14+, Xcode 26 (`xcodebuild` and the Swift 6 toolchain), Go (see `go.mod`).

## Build and run

    macos/build.sh          # → macos/.build/Throwntom.app
    open macos/.build/Throwntom.app

On first launch the app registers its bundled launchd agent
(`com.jwp23.throwntom.daemon`), which starts `throwntomd` and keeps it alive.
macOS shows a "Background item added" notification; nothing to approve. The
agent appears in System Settings → General → Login Items.

The app never spawns the daemon itself. If the socket is unreachable it
reconnects with backoff and, after three failures, re-registers the agent.

If the agent is enabled in Login Items but launchd has no job for it (after a
`bootout`, or a rebuild), the app unregisters and re-registers it after three
failed connection attempts; the menu bar shows "Starting timer…" meanwhile.

## Tests

    cd macos/Throwntom && swift test

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
- `tools/tomctl state` / `tools/tomctl events` show what the app sees.

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
- `build.sh`, `agent.sh` — build and dev-agent scripts.
