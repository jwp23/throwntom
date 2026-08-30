# ADR-006: Daemon lifecycle and config reload

## Context

ADR-001 made `throwntomd` a long-running daemon under launchd with
`KeepAlive`, and ADR-003 made the macOS app a client that owns presentation.
Three behaviours were left as accidents of implementation rather than
decisions, and all three were hit for real on 2026-08-27:

1. There is no user-facing way to stop or start the daemon. Quitting the app
   leaves it running; the only controls are `launchctl bootout` and
   `tools/tomctl`.
2. An in-flight phase survives a daemon restart. `session.json` stores an
   absolute `phase_end_at`, so a phase keeps counting while the daemon is
   down; stopping it for an hour silently expires a 25-minute phase.
3. Config is read only at daemon startup, and a restored phase keeps its
   original `phase_end_at`. Setting `work_minutes = 1` and restarting changes
   nothing, and nothing tells the user the new value is not in effect.

## Decision

1. **The app exposes Start and Stop for the timer service.** Quitting the app
   does not stop the daemon. The daemon exists to keep people on track who
   may forget the app; it is deliberately independent of any client. Stopping
   it is an explicit, discoverable action in the window and menu bar, not a
   side effect of closing a client.
2. **A phase survives a daemon restart and counts through downtime.** A
   pomodoro is wall-clock time; the daemon restores the in-flight phase from
   its absolute end time exactly as today. This is now a decision rather than
   an accident.
3. **Config changes apply immediately, including to the in-flight phase.**
   The daemon reloads its config on change and re-derives the current phase
   from the new durations, so a user who edits `work_minutes` sees the effect
   at once, with no restart.

> Superseded in part 2026-08-30 by
> [ADR-008](008-elapsed-time-survives-a-restart-durations-do-not.md): decisions
> (2) and (3) left one case undecided — a duration edited while the daemon was
> stopped — and ADR-008 settles it. Decisions (1) and (3) stand as written.

> Superseded in part 2026-08-30 by
> [ADR-009](009-a-stopped-timer-service-stays-stopped.md): decision (1) did not
> say how long a stop lasts, and the implementation made it last one app
> session. ADR-009 settles it — a stop persists across launches — and adds the
> window's obligation to say so. The rest of decision (1) stands as written.

## Trade-offs

Start/Stop gives the user an off switch that quitting the app does not, at
the cost of a launchd control path (`bootout`/`bootstrap`) in the client and
a state the window must render when the service is stopped.

Counting through downtime means a stopped daemon can expire a phase the user
never saw finish. That is accepted: the alternative, pausing on stop, would
make "stop the service" and "pause the timer" overlap, and the user already
has Pause for that.

Immediate config reload removes the "restart to apply" footgun but adds a
watcher and a re-derivation of the current phase; a shorter duration than
the elapsed time ends the phase on reload, which is the correct reading of
the user's intent.
