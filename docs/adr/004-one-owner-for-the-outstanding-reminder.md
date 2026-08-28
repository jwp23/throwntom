# ADR-004: One owner for the outstanding reminder

## Context

throwntom raises two reminders. The morning reminder nudges you to start the
day when the schedule triggers and nothing is running. The cycle reminder
nudges you to confirm the next phase once a period completes.

They are the same concept: a repeating nudge, bounded by `repeat_limit_secs`,
suppressible until a deadline, cancelled by an answer. They are implemented
twice.

The morning reminder lives in `internal/core`'s `reminderState`. It owns
`snoozeUntil`, a one-second scheduler tick that consults it, an expiry
goroutine that clears it, and `startMorningLoop`/`stopMorningLoop`.

The cycle reminder lives in `internal/app`'s `App`. It owns a one-shot `after`
timer and `startReminderLocked`/`stopReminderLocked`. It publishes nothing.

That asymmetry is a bug, tracked as throwntom-ux2. `snooze_until` in the state
document is only ever written by the morning path, so a cycle snooze leaves
`state` at `awaiting_confirm` and `snooze_until` at null for its whole
duration. Nothing observable changes. The macOS client decides whether to show
a reminder banner by comparing consecutive states, so it correctly posts one
banner and then, when the snooze expires and the daemon resumes the sound,
posts nothing — a sound with no banner and no way to answer it. That is the
same symptom recorded in throwntom-5ak.

Two questions had to be settled before the fix.

**Does a cycle snooze belong in the product at all?** It predates the current
work — it is in the initial commit, exposed in the popover and on the reminder
notification. But it had never been used: the workflow in the TUI was to snooze
only in the morning and to use `stop` when a pomodoro or break nudge was
unwelcome. `stop` is lossy in ways that are not visible. `Engine.Stop()` sets
`lastPhase = Idle`, and `NextPhase()` derives from `lastPhase`, so the break
just earned is silently forgotten and the next `start` runs a work period
instead. `handleStop` also clears the focused tasks. The block counter survives,
so the long-break cadence keeps advancing over skipped short breaks. A cycle
snooze preserves all three. The verb was right and undiscovered, not wrong.

**Which layer should own the deadline?** Three options:

1. `internal/core` sets and clears `snoozeUntil` around both paths. The cycle
   snooze expires inside `App`'s `after` callback, which `core` cannot see, so
   `core` needs a second expiry timer of its own. That timer would use real
   `time.Sleep` while `App` uses its injected `after`, giving one deadline two
   clocks that drift apart under test.
2. `App` publishes its deadline on `Snapshot` and `core` reads it. Small and
   correct, and a snooze would survive a restart, but it leaves the duplication
   and gives one JSON field two producers.
3. Unify the concept behind one owner.

## Decision

Option 3.

At most one reminder is outstanding at any moment — the morning reminder only
fires while idle, the cycle reminder only at `awaiting_confirm`, and those
states are mutually exclusive. So this needs one reminder, not two objects with
two deadlines.

`internal/core` owns it. `core` is already the composition root: it constructs
the cycle and registers a change hook on it, so it already sees every
transition that raises or answers a reminder.

Consequences:

- `internal/app` leaves the reminder business. It drops its `notifier` and
  `reminderPolicy` constructor parameters — the reminder sound was their only
  use — along with `startReminderLocked`, `stopReminderLocked` and
  `reminderCancel`. What remains is the engine and its wall-clock timers.
- `snooze_until` has one producer and one meaning: the deadline the outstanding
  reminder is suppressed until.
- throwntom-ux2 stops being a bug rather than being fixed. There is no second
  path left to forget to publish from.
- The daemon decides whether a reminder is outstanding by comparing
  transitions, which is the same shape the macOS client already uses to decide
  whether a banner is outstanding.

The reminder must be driven from a **synchronous** transition hook. The
existing hook publishes asynchronously, and hanging reminder lifecycle off it
would let a cancel overtake a raise and leave a reminder ringing after it was
answered. Publishing stays asynchronous; reminding does not.

`internal/app` is renamed to `internal/pomodoro`, and its `App` type to
`Timer`. `internal/engine` already owns the state machine; this package is the
engine with a wall clock on it, which is what a pomodoro timer is. The present
name collides with the macOS app, which is a different program in a different
language that this ADR's own subject matter is often confused with. `cycle`
was considered and rejected: it names the engine's cadence, not this layer's
job, and needed explaining. The package's private `timer` interface becomes
`stopper` so the exported type can take the name. The persisted session
document's `app` key is renamed to `timer` to match; an existing
`session.json` loses its saved position once.

## Trade-offs

We gain one reminder concept with one lifecycle, one clock, and one published
field, and we remove a dependency and a responsibility from the package that
should only be keeping time. A third reminder kind — throwntom-8pc wants the
morning reminder to reach the macOS client as a banner — becomes another
caller of the existing owner rather than a third copy of the lifecycle.

We pay for it with the largest of the three diffs, across `core`, `app` and the
call sites of both, in code that works today apart from the one bug. The
mechanical rename is separated from the behavioural change so the latter is
reviewable on its own.

We also accept that reminders are now raised from `core`'s view of a
transition rather than from inside the component that made it. That is a
slightly longer path from cause to effect, and it is the reason the hook must
be synchronous.

Two related defects are deliberately left out of scope and tracked separately:
`stop` silently discarding the earned break and the focused tasks, and the
discoverability problem that hid the cycle snooze in the first place. The
latter overlaps throwntom-ii1, which would make the TUI a client of the daemon
rather than a second owner of state.
