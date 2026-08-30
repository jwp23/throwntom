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

## Amendment: what (2) preserves

Decisions (2) and (3) were read as contradicting each other during
implementation, so the boundary between them is stated here explicitly.

(2) is about **elapsed time**, not about durations. What survives a restart is
the time the phase has already spent: it keeps accruing while the daemon is
down. It does **not** freeze the duration that time is measured against.
Durations are always read from the current config, whether the edit was made
with the daemon running or stopped — (3) applies on restore exactly as it
applies to a reload.

So editing `work_minutes` from 25 to 50 with the daemon stopped, then
restarting ten minutes into the phase, leaves forty minutes — the same result
as making that edit with the daemon running. Reading (2) as "the old duration
is preserved across a restart" would reinstate the bug (3) was written to
kill: setting `work_minutes = 1` and restarting left the in-flight phase
untouched, and the user who had done everything right saw nothing change.

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
