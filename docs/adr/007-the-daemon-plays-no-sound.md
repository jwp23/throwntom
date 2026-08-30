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
`sound_command = ["true"]` and the scratch-`HOME` runner in
`tools/dev-quiet.sh` were the only mute switches either program had.

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
- On macOS the nag keeps its cadence. Joe's requirement, 2026-08-29: "I do
  want the repeated chime since that's the best reminder that I won't play."
  A single chime plus a persistent banner is not enough — the repeat is the
  part of the reminder that actually works. So the repeat loop reaches the
  client: the daemon rings on its existing cadence, bounded by
  `repeat_limit_secs`, and the client makes each ring audible. The daemon
  still plays nothing itself; it publishes the ring and the client sounds it.
- `sound_command` and the system sound names describe the TUI only.
  `repeat_limit_secs` still bounds both, because it bounds the daemon's ring
  cadence rather than any one program's audio.
- On macOS the reminder is now only as audible as the user's notification
  settings allow. `afplay` bypassed all of it; a banner's sound is subject to
  Focus and to the notification settings for Throwntom, and a user who denies
  notifications outright is left with the Dock bounce alone. Which settings
  silence a banner is macOS's behaviour rather than this app's, and is not
  asserted here beyond that.
  The mitigation is partial and worth stating exactly: `ReminderAuthorization`
  reads `UNAuthorizationStatus`, so the app tells the user when notifications
  are denied or not yet allowed, and points at System Settings. It cannot see
  Focus or a per-app sound setting, so a reminder silenced that way is
  silenced with no explanation. The loss of a sound nothing could silence is
  real regardless.
- `test-sound` over the daemon API plays nothing while reporting success:
  `handleTestSound` returns "Sound test played." whenever `PlaySound` returns
  no error, which `Silent()` always does. It is a TUI command that the
  daemon's generic command endpoint also happens to expose; making it honest
  is throwntom-9vv.

> Superseded in part 2026-08-30 by
> [ADR-009](009-the-chime-is-the-only-audio-path.md): the banners no longer set
> `content.sound`, and the `NSSound` chime this ADR's trade-offs introduced is
> the only audio path. Everything else here stands — the daemon plays nothing,
> and the ring cadence is still published for the client to sound.

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

The repeat loop does reach the macOS client: a chime per repeat, not one per
banner. An earlier draft of this ADR left that open and guessed that a
persistent banner made the repeat unnecessary. Joe rejected that on
2026-08-29 — the repeated chime is the reminder he does not ignore — so the
cadence is published rather than dropped, and the client sounds each ring.

The cost is real and accepted: the reminder cadence now crosses the daemon's
boundary, so a client must be told about a ring rather than deriving it from
state alone. It stays the daemon's cadence, not a second one invented in each
client, which is what keeps `repeat_limit_secs` meaning one thing.
