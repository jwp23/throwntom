package pomodoro

import (
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// SetPausedTooLongAfter sets how long a pause may last before the Timer calls
// it too long, and re-measures a pause already in flight against it: an
// edited threshold lands on the pause the user is in, the way an edited
// duration lands on the phase they are in.
func (t *Timer) SetPausedTooLongAfter(d time.Duration) {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.mu.Unlock()
	t.pausedTooLongAfter = d
	t.armPauseWatchdogLocked()
}

// PausedTooLongAfter is the threshold in force.
func (t *Timer) PausedTooLongAfter() time.Duration {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.pausedTooLongAfter
}

// PausedTooLong reports whether the pause in flight has outlasted the
// threshold. It is derived from the clock rather than recorded, so it is the
// same answer whether the watchdog has fired, is still pending, or was never
// armed at all.
func (t *Timer) PausedTooLong() bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.pausedTooLongLocked()
}

func (t *Timer) pausedTooLongLocked() bool {
	if t.pausedTooLongAfter <= 0 || t.pausedAt.IsZero() || t.engine.State() != engine.Paused {
		return false
	}
	return !t.now().Before(t.pausedAt.Add(t.pausedTooLongAfter))
}

// beginPauseLocked records when a pause started and arms the watchdog for it.
func (t *Timer) beginPauseLocked(startedAt time.Time) {
	t.pausedAt = startedAt
	t.armPauseWatchdogLocked()
}

// endPauseLocked forgets the pause: nothing is paused, so nothing can be
// paused too long.
func (t *Timer) endPauseLocked() {
	t.pausedAt = time.Time{}
	t.stopPauseWatchdogLocked()
}

// armPauseWatchdogLocked schedules the publish that carries the threshold
// being crossed. A pause that is already too long needs none: the change it
// would announce has been announced.
func (t *Timer) armPauseWatchdogLocked() {
	t.stopPauseWatchdogLocked()
	if t.pausedTooLongAfter <= 0 || t.pausedAt.IsZero() || t.pausedTooLongLocked() {
		return
	}
	t.pauseWatchdog = t.after(t.pausedAt.Add(t.pausedTooLongAfter).Sub(t.now()), t.notifyChange)
}

func (t *Timer) stopPauseWatchdogLocked() {
	if t.pauseWatchdog != nil {
		t.pauseWatchdog.Stop()
		t.pauseWatchdog = nil
	}
}

// pauseStartOnRestore reports when the restored pause began. A session with no
// recorded pause start, or one in the future, cannot say — a truncated or
// hand-edited file, or a clock that moved backwards — and neither is evidence
// of a pause the user has already forgotten, so both begin their pause now.
func pauseStartOnRestore(s Snapshot, now time.Time) time.Time {
	if s.PausedAt.IsZero() || s.PausedAt.After(now) {
		return now
	}
	return s.PausedAt
}
