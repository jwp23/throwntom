# ADR-008: Elapsed time survives a restart, durations do not

Supersedes decision (2) of
[ADR-006](006-daemon-lifecycle-and-config-reload.md). Decisions (1) and (3) of
ADR-006 stand unchanged.

## Context

ADR-006 settled three daemon-lifecycle behaviours. Two of them were read as
contradicting each other as soon as anyone tried to implement them.

Decision (2) said a phase survives a daemon restart and counts wall-clock
through the downtime. Decision (3) said config changes apply immediately,
including to the in-flight phase. Both are reasonable read alone. Together
they leave one case undecided: a duration edited **while the daemon is
stopped**. Does the restored phase use the duration it started with, because
(2) says the phase survives — or the duration now in the file, because (3)
says config applies immediately?

The implementation answered (2). Editing `work_minutes` from 25 to 50 with the
daemon stopped and restarting ten minutes in left fifteen minutes, while
making the same edit with the daemon running left forty. The same edit, the
same intent, two different results depending on whether a background process
happened to be alive.

That is the bug decision (3) was written to kill. The incident behind it,
recorded in throwntom-9ig.2, was exactly this shape: setting `work_minutes = 1`
and restarting the daemon left the in-flight phase untouched, and a user who
had done everything right saw nothing change.

The ambiguity also could not be resolved by reading ADR-006 more carefully,
because ADR-006 does not contain the answer. Choosing one is a new decision.

## Decision

Decision (2) preserves **elapsed time**, not durations.

What survives a restart is the time the phase has already spent, and it keeps
accruing while the daemon is down. It does not freeze the duration that time
is measured against. Durations are always read from the current config,
whether the edit was made with the daemon running or stopped, so (3) applies
on restore exactly as it applies to a live reload.

Editing `work_minutes` from 25 to 50 with the daemon stopped, then restarting
ten minutes into the phase, leaves forty minutes — the same result as making
that edit with the daemon running.

This required recording elapsed time as a fact rather than inferring it.
`pomodoro.Snapshot` stored only `PhaseEndAt`, from which elapsed cannot be
recovered once the duration changes; it now also stores `PhaseStartedAt`
(absolute, so downtime counts naturally) and `PausedElapsed` (a pause freezes
the clock, so elapsed can no longer be read from the start alone).

## Trade-offs

We gain one rule instead of two: live reload and restore now derive the
remaining time the same way, from the same recorded facts, so the two paths
cannot drift apart.

We give up the ability to treat a restart as a way to hold a phase at the
duration it began with. Nothing asked for that, and the alternative reading
reinstates the bug (3) exists to prevent.

A duration shortened below the time already elapsed ends the phase on restore.
That follows from applying current durations and is the correct reading of the
user's intent: they shortened the phase, and it is over.
