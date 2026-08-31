# ADR-009: The chime is the only audio path

Supersedes the part of [ADR-007](007-the-daemon-plays-no-sound.md) that gives
the macOS reminder banners a sound of their own. The rest of ADR-007 stands:
the daemon plays nothing, `cmd/throwntomd` injects `notifier.Silent()`, and
the ring cadence is published so the client can sound each repeat.

## Context

ADR-007 moved reminder audio out of the daemon and into the macOS client, and
said how the client would make a reminder audible: the banners set
`content.sound = .default`, "so both the cycle reminder and the morning nudge
chime as they post". That was the whole audio path as the decision was
written.

Then Joe added a requirement in the same breath, recorded in ADR-007's own
trade-offs: the repeated chime is the reminder he does not ignore. A banner
sound cannot provide a repeat. It fires once, when the banner posts, and the
repeat rings raise no further banner — deliberately, because a banner per ring
would leave a pile of them to dismiss. So a second audio path was added: the
client sounds each published ring with `NSSound`
(`SystemReminderPresenter.chime()`).

Both landed in the same pull request, #121. Nobody removed the first. One
requirement — make the reminder audible — ended up with two implementations
that overlap on the first ring, because the daemon's first ring and the banner
arrive together:

- `reminder.Loop.Run` calls `notify()` immediately, before it creates its
  ticker (`internal/reminder/loop.go:49`). There is no initial delay.
- Entering `AwaitingConfirm` sets `rings = 0` and starts that loop
  (`internal/core/outstanding.go:99`, `:213`), and `ring()` increments it
  (`:223`).

So `reminderRings` climbs 0 → 1 within microseconds of the phase becoming
`AwaitingConfirm`. The banner posts with its sound *and* the ring-driven chime
sounds, both at ring one.

This survived because the guard against it was keyed to the wrong condition.
`chimeForNewRings` skipped the chime while `heardRings` was `nil`, which the
code described as keeping a reconnect quiet. It does not: `ReminderResponder`
is built once (`AppEnvironment.swift:22`) and `heardRings` is never reset, and
`DaemonClient.state` returns to `nil` only in `stopService()`
(`DaemonClient.swift:119`). `nil` therefore meant "this app has not read any
state yet" — app launch, once per process. Every wait after the first one
following launch double-sounded, and the tests missed it because they all
started from no prior state, the single case the guard covered.

## Decision

The `NSSound` chime is the only audio path on macOS. Neither reminder banner
carries a sound.

> Scope noted 2026-08-31: this decision is about REMINDER audio, which is what
> the context above reasons over — a banner sound and a ring chime doubling on
> ring one. The `NSSound.beep()` on a failed timer verb
> (`DaemonDispatch.swift`) is a different event: feedback on a command the user
> just issued, not a reminder, and the two cannot coincide. It predates this
> decision and was never weighed here. The sentence above is not a licence to
> delete it. Nothing decided is changed by saying so.

1. `ReminderAlert`'s shared builder sets no `content.sound`. Nothing audible
   is lost: the chime sounds ring one at the moment the banner posts.
2. `chimeForNewRings` keys off a ring count that starts at zero rather than an
   optional. Ring one is sounded like every other ring, for every wait, not
   only the first after launch.
3. A climb of any size is one chime, not one per ring missed. Rings the app
   was not there to hear — across a reconnect, or a wait already running when
   the app started — are past, and what is still owed is a single reminder
   rather than a backlog of alerts. This also removes a real burst: the
   previous loop chimed once per missed ring.
4. The authorization request drops `.sound` and asks for `.alert` only, and
   `ReminderResponder.presentationOptions` drops `.sound` too. Both existed to
   let the banner's sound through; there is no banner sound left for either to
   apply to. This reverses throwntom-8rz, which added the `.sound` option and
   was correctly closed on the facts as they stood then — the banners did
   carry `content.sound`, and the grant was genuinely needed for it.

Consequences:

- A wait that is already ringing when the app starts is now heard. Under
  ADR-007 it was adopted in silence, and with the banner sound removed it
  would otherwise have been silent entirely.
- One assertion changed direction: `testEachNewRingChimes` asserted zero
  chimes at ring one, with the comment "the banner carries the first chime as
  it posts". That assertion encoded the overlap rather than catching it.

### What was verified about suppression, and what was not

ADR-007 declined to say which settings silence a banner, and that restraint is
kept here. Only the sourced half is stated:

- A banner's sound is gated by the per-app sound setting. `soundSetting` on
  `UNNotificationSettings` is documented as the authorization status for
  playing sounds, and the system "tries to play a sound" when
  `UNNotificationContent.sound` has a value — the user-facing control being
  "Play sound for notification" in System Settings › Notifications.
- A banner at the default interruption level is not documented to break
  through Focus. Apple documents only `timeSensitive` ("breaks through system
  notification controls") and `critical` ("bypasses the mute switch", and
  requiring an Apple-issued entitlement) as doing so.

**Not verified, and therefore not claimed:** that `NSSound` playback is immune
to Focus or to per-app notification settings. `NSSound` is documented purely
as AppKit/Core Audio file playback, with no reference to notifications, Focus
or Do Not Disturb — but Apple nowhere states affirmatively that Focus leaves
it alone, and this was not measured on-device. So this ADR does not claim the
change makes reminders harder to suppress. It rests only on removing a
duplicate, not on a suppression difference. If that difference matters later,
it needs an on-device measurement, not a citation.

## Trade-offs

We gain one implementation of one requirement, and a first ring that behaves
like every other ring instead of depending on how long the app has been
running.

We give up the banner's sound as an independent fallback. If the chime fails —
`NSSound(named:)` returns nil for a missing system sound, and the code is
deliberately quiet about it — there is now no second sound behind it. That is
accepted: a fallback that only ever covered ring one, and that doubled it
every time it worked, was not buying much. The banner and the Dock bounce
still carry the reminder visually.
