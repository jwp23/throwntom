package pomodoro

import (
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// ApplyDurations replaces the phase durations and re-derives the phase in
// flight from the new ones: the phase keeps the time it has already spent and
// runs for whatever the new duration leaves. A new duration shorter than the
// elapsed time means the phase should already be over, so it ends at once.
//
// Every argument must be positive, as New requires: these come from a
// validated config.Config, and longBreakEvery is a divisor.
func (t *Timer) ApplyDurations(workMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery int) {
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

	elapsed, running := t.elapsedInPhaseLocked(state)

	t.workDuration = time.Duration(workMinutes) * time.Minute
	t.shortBreakDuration = time.Duration(shortBreakMinutes) * time.Minute
	t.longBreakDuration = time.Duration(longBreakMinutes) * time.Minute
	t.engine.SetLongBreakEvery(longBreakEvery)
	if !running {
		return
	}

	remaining := t.phaseDurationLocked(t.pausedAwareStateLocked(state)) - elapsed
	if state == engine.Paused {
		t.applyToPausedLocked(remaining)
		return
	}
	if remaining > 0 {
		t.startPhaseTimerLocked(remaining)
		return
	}
	t.completePeriodLocked()
}

// elapsedInPhaseLocked reports how long the current phase has run under the
// durations in force before the change, and whether there is a phase to
// re-derive at all.
func (t *Timer) elapsedInPhaseLocked(state engine.State) (time.Duration, bool) {
	switch state {
	case engine.Work, engine.ShortBreak, engine.LongBreak:
		if t.phaseEndAt.IsZero() {
			return 0, false
		}
		return t.phaseDurationLocked(state) - t.phaseEndAt.Sub(t.now()), true
	case engine.Paused:
		return t.phaseDurationLocked(t.engine.Snapshot().PausedFrom) - t.pausedRemaining, true
	default:
		return 0, false
	}
}

// applyToPausedLocked keeps a paused phase paused with its re-derived
// remainder, or ends it when the new duration has already been served.
func (t *Timer) applyToPausedLocked(remaining time.Duration) {
	if remaining > 0 {
		t.pausedRemaining = remaining
		return
	}
	t.pausedRemaining = 0
	t.engine.Resume()
	t.completePeriodLocked()
}

// pausedAwareStateLocked names the phase a state is counting down, which for
// Paused is the phase it was paused from.
func (t *Timer) pausedAwareStateLocked(state engine.State) engine.State {
	if state == engine.Paused {
		return t.engine.Snapshot().PausedFrom
	}
	return state
}

func (t *Timer) phaseDurationLocked(state engine.State) time.Duration {
	switch state {
	case engine.Work:
		return t.workDuration
	case engine.ShortBreak:
		return t.shortBreakDuration
	case engine.LongBreak:
		return t.longBreakDuration
	default:
		return 0
	}
}
