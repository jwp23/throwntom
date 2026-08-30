# Developing throwntom

How to drive the daemon and the macOS app from a terminal. Most of this exists so that a coding
agent can build, run and *look at* the app on its own — without a human watching — and it works
just as well for a developer at a terminal. The TUI is covered at the end; everything else here is
about the daemon and the macOS app.

## The daemon from the command line

`tools/tomctl` talks to a running `throwntomd` over `~/.config/throwntom/daemon.sock`:

```bash
go build -o tomctl ./tools/tomctl           # or prefix each call with: go run ./tools/tomctl
./tomctl state                              # the State document (see docs/designs/native-macos-client.md)
./tomctl events                             # one State per line as it changes, until Ctrl-C
./tomctl cmd pause                          # also: resume, stop, confirm, snooze 10m, skip-today, new-cycle
./tomctl cmd task add "write tests"
```

`tomctl cmd` runs the same command grammar as the TUI. `start` and `confirm` prompt for task focus in
that grammar and fail non-interactively ("invalid input during task selection"); use the timer routes
the app uses instead — they never prompt:

```bash
curl -s --unix-socket ~/.config/throwntom/daemon.sock -X POST http://d/v1/timer/start
curl -s --unix-socket ~/.config/throwntom/daemon.sock -X POST http://d/v1/timer/confirm
```

`stop` idles the timer; it does not stop the daemon. The daemon runs under launchd with `KeepAlive`,
so quitting the app leaves it — and its end-of-phase reminder — running. Quit the app first (an open
app re-registers the agent after three failed connections), then:

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

in `~/.config/throwntom/config.toml`, then a daemon restart (quit the app, `bootout` above, open the
app again). Back
up `session.json`, `events.jsonl` and `tasks.json` from `~/.config/throwntom` first and restore them
after: the tour writes completed pomodoros into today's stats. Remove the `[pomodoro]` block afterwards.

## Seeing the app without a human

This section is for autonomous verification: an agent (or a script) changes the daemon's state,
captures what the window shows, and compares. It is also, in effect, a way to drive the app
programmatically — everything the window *shows* follows the daemon, so the timer routes and
`tomctl` are a complete remote control for the timer and tasks. What they cannot do is press the
window's own controls (panels, the shortcut sheet); there is no AppleScript or accessibility
automation, and no use case for one so far.

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

## The README banner

`docs/images/throwntom.png` is generated, not hand-edited. The art was exported opaque over an
off-white backdrop, which reads as white blocks on a dark-themed page, so the committed source
keeps that original and the banner is regenerated with a real alpha channel:

```bash
tools/unmatte-white-background.swift docs/images/throwntom-source.png docs/images/throwntom.png
tools/unmatte-white-background.swift --verify docs/images/throwntom-source.png docs/images/throwntom.png
```

The tool flood-fills the backdrop inward from the four corners, so white *inside* the art — the
badge ring, the wordmark outline — is enclosed by opaque pixels and is never reached, and it
un-composites each background pixel from the backdrop colour it samples at the corner. The soft
edge keeps its exact coverage, so the banner over white is the original pixel for pixel while the
corners are fully transparent. `--verify` asserts exactly that and exits non-zero otherwise; run it
after any regeneration. The reported surround percentage (about 4.6%) is the leak check: a fill
that escaped into the artwork would claim most of the image.

Do not apply `macos/mask-icon.swift` here. That masks the *app icon* to Apple's continuous-corner
squircle, and the banner is different art with a soft, full-bleed edge of its own — a geometric
mask fits it no better than 5px and would clip the artwork.

## The macOS dev loop

`macos/install.sh` quits the app, stops the agent, rebuilds (about a minute), copies the bundle to
`~/Applications` and opens it; allow up to half a minute of "Starting timer…" after that. The
launch-agent label is shared by every build, so whichever bundle you opened last owns the
registered daemon.

Launch Services is keyed the same way, on the bundle id, and is worse in one respect: deleting a
worktree does not remove the registration it left behind, so dead entries accumulate and outlive
the directories they name. macOS is then free to resolve the app through a bundle that is no longer
on disk, and nothing about the symptom points at Launch Services. `macos/build.sh` prunes
registrations whose bundle is gone, so the loop heals itself; `go run ./tools/lsreg list` shows what
is registered, and `prune` cleans it on demand (see `tools/lsreg/README.md`). Never run `lsregister
-kill -r -domain local -domain system -domain user` — the flag is undocumented and is widely
reported to rebuild the whole machine's database.

This pileup was investigated as the cause of the missing notification icon in throwntom-3ll and
ruled out: cleaning it up did not bring the icon back. It is a dev-loop hazard in its own right.

## The terminal UI

The TUI runs the engine in-process and does not use the daemon (throwntom-ii1 tracks making it a
client). Run it from source with `go run ./cmd/throwntom`, or safely while a real session is running
with `tools/dev-quiet.sh` (throwaway `HOME`, silent). Its tests are the Go unit tests
(`go test -timeout 30s ./...`), the integration tests (`-tags=integration ./integration`) and the
end-to-end tests (`-tags=e2e ./e2e`); the pre-commit hook runs the unit tests. Do not run the TUI and
the daemon at the same time — they share `~/.config/throwntom/session.json`.
