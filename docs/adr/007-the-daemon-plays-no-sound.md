# ADR-007: The daemon plays no sound

## Context

ADR-003 moved user-facing notification into the clients: the daemon owns
timing and state and publishes changes on `/v1/events`, and each client
presents them on its own platform. Its trade-offs section said the rest out
loud — "the daemon should not play a sound that nothing is present to answer
— the reminder is a client concern too" — and `CLAUDE.md` restates it as a
rule. The notification path was moved; the sound path was not touched.

So `throwntomd` kept a `notifier.Notifier`, and it is the only thing that
makes a reminder audible. `internal/notifier` switches on `runtime.GOOS`,
names macOS system sounds, shells out to `afplay`, and falls back through
`paplay`, `canberra-gtk-play` and `aplay` — platform presentation inside the
portable core, the same class of thing ADR-003 removed for notifications.
`tools/dev-quiet.sh` and `sound_command = ["true"]` exist because there was
otherwise no way to make the daemon stop.

The obvious reading of throwntom-u69 — suppress the sound when `/v1/events`
has no subscribers — is wrong in both directions. The TUI is not a client of
the daemon: `cmd/throwntom` builds its own `core.New` in-process and nothing
subscribes to it, so a TUI core has zero subscribers permanently and would go
silent. And a subscriber that presents nothing — `tomctl`, a test, a future
watcher — would turn the sound back on. Subscriber count is a transport fact,
and reminder policy is not the place to read it.

## Decision

The reminder sound is decided by the composition root, not by `internal/core`.

`internal/notifier` gains `Silent()`, a notifier that plays nothing.
`cmd/throwntomd` injects it; `cmd/throwntom` keeps `NewSystemNotifier`. Core
is unchanged: it already takes a `notifier.Notifier` and asks it to play, and
which notifier that is was always the caller's business.

The macOS client takes over the audio it was already going to be responsible
for. Its reminder banners set `content.sound = .default`, so both the cycle
reminder and the morning nudge chime as they post. Sound and buttons now
arrive together, from the process that can answer them.

Consequences:

- The daemon is silent on every platform. A user running `throwntomd` with no
  client gets state on `/v1/events` and nothing else. That is ADR-003's
  intent, not a regression: quitting the client is the off switch.
- The TUI is unchanged — audible, with the repeat loop, on macOS and Linux.
  It presents its own reminders because it is its own core, not a client.
- On macOS the nag changes shape: one chime and one persistent banner, rather
  than a sound repeated until the bound in `repeat_limit_secs` is reached. The
  banner does not go away by itself, so the reminder is still outstanding
  until it is answered; it just stops being loud about it.
- `sound_command` and the system sound names now describe the TUI only.
- `test-sound` over the daemon API plays nothing while reporting success. It
  is a TUI command that the daemon's generic command endpoint also happens to
  expose; making it honest is tracked separately.

This depended on throwntom-8pc, which gave the morning nudge a macOS banner of
its own. Before that the morning reminder was sound only on macOS, and
silencing the daemon would have removed it from the platform entirely.

## Trade-offs

We gain a daemon that is portable in behaviour and not only in build tags, and
a reminder whose sound, banner and buttons all belong to the process the user
can see and quit. The `runtime.GOOS` switch in `internal/notifier` is still
there, but only the TUI's own main reaches it.

We give up audible reminders for a headless daemon on Linux with no client
attached. Nothing presents that configuration today, and giving it sound back
means giving it a client, which is the shape ADR-003 asks for anyway.

Whether the repeat loop should reach the macOS client at all — a chime per
repeat rather than one per banner — is deliberately left open. It would mean
publishing a ring as an event rather than a state, and duplicating the
reminder cadence into every client, which is not worth it for one repeat that
a persistent banner already covers.
