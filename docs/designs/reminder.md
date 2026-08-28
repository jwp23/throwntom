# Reminder

The reminder is the repeating nudge the daemon plays when it is waiting on
you: in the morning, when the schedule says the day should start and nothing
is running, and after every period, when the next phase needs confirming. This
document describes its owner, its lifecycle, and how the rest of the daemon
drives it. ADR-004 records why it is built this way.

## Layers

The pomodoro lives in three packages, each with one job:

- `internal/engine` is the state machine: which phase you are in, the block
  counter, what comes next. It has no clock.
- `internal/pomodoro` is `Timer`: the engine with a wall clock on it. It
  starts a countdown for each phase, pauses and resumes it, ends the period
  when the countdown fires, and re-arms it after a restart. It knows nothing
  about reminders.
- `internal/core` composes them with commands, tasks, session persistence,
  state publishing, the schedule, and the reminder.

## One reminder

At most one reminder is outstanding at any moment. The morning reminder only
fires while idle; the cycle reminder only at `awaiting_confirm`; those states
are mutually exclusive. So `core` holds a single `outstandingReminder` value, not one per
kind.

```go
type outstandingReminder struct {
    mu             sync.Mutex
    kind           reminderKind // none | morning | cycle
    snoozeUntil    time.Time    // non-zero: outstanding but suppressed
    lastTriggerDay string       // the morning reminder fires once a day
    loopCancel     context.CancelFunc
    snoozeTimer    stopper
    policy         reminder.Policy
    sound          func(reminderKind) error
    now            func() time.Time
    after          func(time.Duration, func()) stopper
    onChange       func()
}
```

`kind` answers "is a reminder outstanding". `snoozeUntil` answers "is it
quiet right now". `internal/reminder` supplies `Policy` (ring every
`repeat_secs`, for at most `repeat_limit_secs`) and `Loop`, the goroutine that
rings until cancelled or exhausted; they are unchanged.

`now` and `after` default to the real clock; `stopper` is `core`'s own
one-method interface over the handle `after` returns, the same shape
`pomodoro` keeps privately. Tests inject the same fake clock into
`pomodoro.Timer` and the reminder so a deadline has one clock.

### Operations

All four take `mu` and call `onChange` when something observable changed.

- `raise(kind)` — no-op if that kind is already outstanding, so a repeated
  schedule tick or a restore cannot double-ring. Otherwise cancel any running
  loop, set `kind`, and start a `Loop` that plays that kind's sound
  (`morning` or `default`).
- `suppress(until)` — refused when nothing is outstanding. Stops the loop,
  records `snoozeUntil`, and schedules `resume` for the deadline. `kind` is
  kept: the reminder is outstanding and quiet.
- `resume()` — the deadline callback. If the reminder is still suppressed,
  clears `snoozeUntil` and restarts the loop, ringing immediately. If it was
  cancelled or replaced in the meantime, does nothing.
- `cancel()` — clears `kind` and `snoozeUntil`, stops the loop and the snooze
  timer.

### Sources

Two places raise and cancel. There is no registration API; both are `core`'s
own code, and a third kind, should one appear, is a third caller.

1. **Timer transitions.** `pomodoro.Timer` exposes
   `SetOnTransition(func(to engine.State))`, called synchronously, inside the
   timer's lock, on every transition: command-driven, countdown-driven and
   `Restore`. `core`'s handler raises the cycle reminder when `to` is
   `awaiting_confirm` and cancels otherwise. Because leaving idle is a
   transition, the same handler retires the morning reminder. The one handler
   that cancels by hand is `start`, which may enter the focus prompt before
   any transition happens and must not leave the reminder ringing through it.

   The hook is synchronous so that a cancel cannot overtake a raise. The
   existing `SetOnChange` hook stays asynchronous and only publishes state.

2. **The schedule tick.** The one-second goroutine raises the morning
   reminder when the timer is idle, the schedule triggers, and it has not
   fired today.

Lock order is `core.mu`, then `pomodoro.Timer`'s lock, then `reminder.mu`,
never reversed. The reminder never calls back into the timer; the schedule
tick holds the core lock across its idle check and raise, so a command
cannot slip between them.

## Commands

- `snooze <d>` calls `suppress(now + d)`. With nothing outstanding it is
  refused (`ErrorRefused`, "nothing to snooze: no reminder is outstanding").
  A non-positive `d` is a usage error. Snoozing during a snooze replaces the
  deadline. The reply names the kind: "morning reminder snoozed for 10m".
- `skip-today` cancels and stamps `lastTriggerDay`, so the morning reminder
  does not fire again today.
- `new-cycle`, `confirm`, `stop` cancel through the transition hook; `start`
  cancels first, before its focus prompt.
- `quit` and `Core.Stop()` cancel directly.

A morning snooze resumes on its deadline whether or not the schedule window
is still open: the snooze is the user's instruction.

## Published state

`snooze_until` has one producer and one meaning: the deadline the outstanding
reminder is suppressed until. `morning_pending` is `kind == morning`, and so
stays true through a morning snooze. A cycle reminder is outstanding exactly
when `state` is `awaiting_confirm`; no field is added for it.

Clients decide whether to present a reminder by comparing consecutive states,
so a snooze expiring is visible to them as `snooze_until` returning to null.

## Restart

Nothing about the reminder is persisted. `session.json` holds the timer's
snapshot under `timer`; on load, `Timer.Restore` fires the transition hook,
and landing in `awaiting_confirm` raises the cycle reminder. The morning
reminder is raised by `Core.Start` when the config marks it pending, the timer
is idle, and the schedule is active; a session restored in any other state
marks the morning reminder as already owed for today, without cancelling the
reminder the restore itself raised.

A snooze does not survive a restart: the reminder rings again as soon as the
daemon is back. Persisting the deadline is one field on the session document
and one `suppress` on load, if it is ever wanted.

## Testing

- The reminder type is unit-tested with a fake clock and a notifier that
  records which sound played: raise is idempotent per kind and replaces the
  other kind; suppress then resume restarts the loop; cancel during a snooze
  leaves the deadline callback inert; a second snooze replaces the deadline;
  `onChange` fires only on observable change.
- Core command tests cover the published behaviour: snooze at
  `awaiting_confirm` publishes `snooze_until`, expiry publishes null and rings
  again; snooze with nothing outstanding is refused; `morning_pending` stays
  true through a morning snooze; a transition during a snooze cancels it.
- `pomodoro.Timer` tests prove `SetOnTransition` runs synchronously with the
  right `to` for every verb, for a countdown firing, and for `Restore`. The
  package has no reminder tests; that coverage lives in `core`.
- `internal/reminder`'s `Loop` tests are unchanged. The macOS client needs no
  change: it reads `morning_pending` only to offer the snooze action, which
  is correct while a snooze is running.
