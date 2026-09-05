package pomodoro

import (
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// Durations is how long each phase runs and how many pomodoros make a block.
// It is a record rather than a list of arguments because every field is an
// int and four of them are minutes, so a positional call says nothing about
// which is which. The field names are the config keys they come from.
//
// Every field must be positive, as New requires: these come from a validated
// config.Config, and LongBreakEvery is a divisor.
type Durations struct {
	WorkMinutes       int
	ShortBreakMinutes int
	LongBreakMinutes  int
	LunchMinutes      int
	LongBreakEvery    int
}

// ApplyDurations replaces the phase durations and re-derives the phase in
// flight from the new ones: the phase keeps the time it has already spent and
// runs for whatever the new duration leaves. A new duration shorter than the
// elapsed time means the phase should already be over, so it ends at once.
//
// This is the same rule Restore applies after downtime — elapsed time is a
// fact about the phase, the duration it is measured against always comes from
// the current config — so an edit lands identically whether the daemon was
// running at the time or not.
func (t *Timer) ApplyDurations(d Durations) {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.mu.Unlock()

	state := t.engine.State()
	// Report a transition only when the phase actually ends. Most reloads
	// change nothing about the engine's state, and announcing one anyway
	// would answer whatever reminder is outstanding — cancelling a morning
	// nudge the user has not acknowledged, which only rings once a day.
	defer func() {
		if t.engine.State() != state {
			t.transitionLocked()
		}
	}()

	t.workDuration = time.Duration(d.WorkMinutes) * time.Minute
	t.shortBreakDuration = time.Duration(d.ShortBreakMinutes) * time.Minute
	t.longBreakDuration = time.Duration(d.LongBreakMinutes) * time.Minute
	t.lunchDuration = time.Duration(d.LunchMinutes) * time.Minute
	t.engine.SetLongBreakEvery(d.LongBreakEvery)
	t.engine.SetWorkMinutes(d.WorkMinutes)

	switch state {
	// A meeting is re-derived with the rest although no field here can have
	// changed its length: it was given one at the moment it started rather
	// than taking one from the config. Leaving it out would only mean the one
	// running phase that does not re-derive, and it re-derives to itself.
	case engine.Work, engine.ShortBreak, engine.LongBreak, engine.Lunch, engine.Meeting:
		t.rederiveRunningLocked(state)
	case engine.Paused:
		t.rederivePausedLocked()
	}
}

// rederiveRunningLocked re-runs the phase against its new duration, keeping
// the start it already had so its elapsed time is unchanged.
func (t *Timer) rederiveRunningLocked(state engine.State) {
	if t.phaseStartedAt.IsZero() {
		return
	}
	remaining := t.phaseDurationLocked(state) - t.elapsedSincePhaseStartLocked()
	if remaining <= 0 {
		t.completePeriodLocked()
		return
	}
	t.startPhaseFromLocked(t.phaseStartedAt, remaining)
}

// rederivePausedLocked keeps a paused phase paused with its re-derived
// remainder, or ends it when the new duration has already been served.
func (t *Timer) rederivePausedLocked() {
	remaining := t.phaseDurationLocked(t.engine.Snapshot().PausedFrom) - t.pausedElapsed
	if remaining > 0 {
		t.pausedRemaining = remaining
		return
	}
	t.pausedRemaining = 0
	t.pausedElapsed = 0
	t.engine.Resume()
	t.completePeriodLocked()
}

func (t *Timer) phaseDurationLocked(state engine.State) time.Duration {
	switch state {
	case engine.Work:
		return t.workDuration
	case engine.ShortBreak:
		return t.shortBreakDuration
	case engine.LongBreak:
		return t.longBreakDuration
	case engine.Lunch:
		return t.lunchDuration
	// A meeting's length is the one the user gave it, kept on the Timer
	// because no config field holds it.
	case engine.Meeting:
		return t.meetingDuration
	default:
		return 0
	}
}
