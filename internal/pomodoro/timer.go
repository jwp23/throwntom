package pomodoro

import (
	"fmt"
	"sync"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// stopper cancels a callback scheduled with afterFunc.
type stopper interface {
	Stop() bool
}

// afterFunc schedules fn to run once after d and returns a handle to cancel
// it. It is the only way Timer schedules work in the future, so a test clock can
// replace both it and Timer's now to make timer-driven behavior deterministic.
type afterFunc func(d time.Duration, fn func()) stopper

func realAfterFunc(d time.Duration, fn func()) stopper {
	return time.AfterFunc(d, fn)
}

type Timer struct {
	mu                 sync.Mutex
	engine             *engine.Engine
	workDuration       time.Duration
	shortBreakDuration time.Duration
	longBreakDuration  time.Duration
	now                func() time.Time
	after              afterFunc
	periodTimer        stopper
	// phaseStartedAt is when the running phase's clock began, kept as an
	// absolute time so elapsed is a fact about the phase rather than
	// something inferred from the durations in force. That is what lets a
	// duration edited while the daemon was down apply to the phase that was
	// running: ADR-006 (3).
	phaseStartedAt  time.Time
	phaseEndAt      time.Time
	pausedRemaining time.Duration
	// pausedElapsed freezes how much of the phase was spent when it was
	// paused. A pause stops the clock, so elapsed can no longer be read from
	// phaseStartedAt.
	pausedElapsed time.Duration
	// pausedAt is when the current pause began, and is set only while the
	// engine is paused. A pause freezes the phase but not the wall clock, so
	// this is the one time the Timer keeps that the phase's own clock cannot
	// give back.
	pausedAt time.Time
	// pausedTooLongAfter is how long a pause may last before the Timer calls
	// it forgotten. Zero means never, which is what a Timer built without one
	// has.
	pausedTooLongAfter time.Duration
	// pauseWatchdog publishes the moment the pause in flight becomes too
	// long. Nothing about the answer depends on it firing — PausedTooLong is
	// derived from the clock — but without it the threshold passes with no
	// change for anyone to observe.
	pauseWatchdog stopper
	onChange      func()
	// onTransition runs inside the Timer lock, before the verb returns, every
	// time the engine's state is set: by a verb, by a countdown ending or by
	// Restore. It must not call back into the Timer.
	onTransition func(to engine.State)
}

func New(workMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery int) *Timer {
	return &Timer{
		engine:             engine.New(workMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery),
		workDuration:       time.Duration(workMinutes) * time.Minute,
		shortBreakDuration: time.Duration(shortBreakMinutes) * time.Minute,
		longBreakDuration:  time.Duration(longBreakMinutes) * time.Minute,
		now:                time.Now,
		after:              realAfterFunc,
	}
}

// SetOnChange registers fn to run after every state transition, including
// timer-driven ones. fn runs outside the Timer lock.
func (t *Timer) SetOnChange(fn func()) {
	t.mu.Lock()
	t.onChange = fn
	t.mu.Unlock()
}

// SetOnTransition registers fn to run synchronously, with the Timer lock held,
// after every change of engine state. Use it for work that must be ordered
// with the transition; use SetOnChange for work that may run later.
func (t *Timer) SetOnTransition(fn func(to engine.State)) {
	t.mu.Lock()
	t.onTransition = fn
	t.mu.Unlock()
}

// transitionLocked reports the engine's current state to onTransition.
// Callers must hold t.mu.
func (t *Timer) transitionLocked() {
	if t.onTransition != nil {
		t.onTransition(t.engine.State())
	}
}

func (t *Timer) notifyChange() {
	t.mu.Lock()
	fn := t.onChange
	t.mu.Unlock()
	if fn != nil {
		fn()
	}
}

type Snapshot struct {
	Engine          engine.Snapshot `json:"engine"`
	PhaseStartedAt  time.Time       `json:"phase_started_at"`
	PhaseEndAt      time.Time       `json:"phase_end_at"`
	PausedRemaining time.Duration   `json:"paused_remaining"`
	PausedElapsed   time.Duration   `json:"paused_elapsed"`
	// PausedAt is when the pause began, so a pause survives a restart with
	// its age rather than starting it over.
	PausedAt time.Time `json:"paused_at"`
}

func (t *Timer) Snapshot() Snapshot {
	t.mu.Lock()
	defer t.mu.Unlock()
	return Snapshot{
		Engine:          t.engine.Snapshot(),
		PhaseStartedAt:  t.phaseStartedAt,
		PhaseEndAt:      t.phaseEndAt,
		PausedRemaining: t.pausedRemaining,
		PausedElapsed:   t.pausedElapsed,
		PausedAt:        t.pausedAt,
	}
}

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

func (t *Timer) Restore(s Snapshot, now time.Time) error {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.mu.Unlock()
	defer t.transitionLocked()
	t.engine.Restore(s.Engine)

	switch s.Engine.State {
	case engine.Work, engine.ShortBreak, engine.LongBreak:
		t.restoreRunningLocked(s, now)
	case engine.Paused:
		t.restorePausedLocked(s, now)
	}
	return nil
}

// restoreRunningLocked brings back a phase that was counting down. The time
// spent keeps accruing across the outage — downtime is not a pause — but it
// is measured against the duration in force now, not the one that was in
// force when the session was saved: ADR-008. A phase whose
// current duration has already been served comes back complete.
func (t *Timer) restoreRunningLocked(s Snapshot, now time.Time) {
	startedAt := phaseStartOnRestore(s, now)
	remaining := t.phaseDurationLocked(s.Engine.State) - now.Sub(startedAt)
	if remaining <= 0 {
		t.completePeriodLocked()
		return
	}
	t.startPhaseFromLocked(startedAt, remaining)
}

// phaseStartOnRestore reports when the restored phase began. Two sessions
// cannot say: one whose start is in the future, which is a clock that moved
// backwards, and one with no start at all, which is truncated or hand-edited.
// Neither owes the user time already served, so both count as beginning now —
// and ADR-008 then measures the phase against the duration in force now, with
// no carve-out for a session that happens to be missing a field.
func phaseStartOnRestore(s Snapshot, now time.Time) time.Time {
	if s.PhaseStartedAt.IsZero() || s.PhaseStartedAt.After(now) {
		return now
	}
	return s.PhaseStartedAt
}

// restorePausedLocked brings back a paused phase. Its elapsed time is frozen,
// so only the duration it is measured against can have changed. The pause
// itself keeps ageing across the outage, which is the whole point of a pause
// that has been forgotten: the clock it is measured against is the wall's.
func (t *Timer) restorePausedLocked(s Snapshot, now time.Time) {
	t.pausedElapsed = s.PausedElapsed
	if s.PausedElapsed == 0 {
		t.pausedRemaining = s.PausedRemaining
		t.beginPauseLocked(pauseStartOnRestore(s, now))
		return
	}
	remaining := t.phaseDurationLocked(s.Engine.PausedFrom) - s.PausedElapsed
	if remaining <= 0 {
		t.pausedElapsed = 0
		t.pausedRemaining = 0
		t.engine.Resume()
		t.completePeriodLocked()
		return
	}
	t.pausedRemaining = remaining
	t.beginPauseLocked(pauseStartOnRestore(s, now))
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

func (t *Timer) AdvanceDay(now time.Time) {
	t.mu.Lock()
	before := t.engine.Snapshot()
	t.engine.AdvanceDay(now)
	after := t.engine.Snapshot()
	t.mu.Unlock()
	if dayRolledOver(before, after) {
		t.notifyChange()
	}
}

// dayRolledOver reports whether AdvanceDay started a new work day and reset the
// day's counters. Recording the very first work date is not a rollover: nothing
// an observer can see changes, and notifying on it would make every status read
// look like a state change.
func dayRolledOver(before, after engine.Snapshot) bool {
	return !before.WorkDate.IsZero() && !engine.IsSameDay(before.WorkDate, after.WorkDate)
}

// Start enters the phase the cycle owes and reports the engine state it acted
// from. A phase waiting to be confirmed is owed the phase confirm would begin,
// so start does what confirm does at that boundary. Deciding it inside the
// lock is what makes it safe: the phase deadline fires from its own goroutine
// and can reach that boundary between a caller's own check and this call, and
// a start that then began fresh work would discard the completion the caller
// still has to log. The returned snapshot names the phase that completion
// belongs to.
func (t *Timer) Start() engine.Snapshot {
	t.mu.Lock()
	before := t.engine.Snapshot()
	defer t.notifyChange()
	defer t.mu.Unlock()
	defer t.transitionLocked()
	if before.State == engine.AwaitingConfirm {
		t.confirmNextLocked()
		return before
	}
	t.engine.StartWork()
	t.startPhaseTimerLocked(t.phaseDurationLocked(t.engine.State()))
	return before
}

// confirmNextLocked credits the phase waiting on the user and runs the one
// that follows. A stage with no duration of its own runs no timer.
func (t *Timer) confirmNextLocked() {
	t.engine.ConfirmNext()
	if d := t.phaseDurationLocked(t.engine.State()); d > 0 {
		t.startPhaseTimerLocked(d)
	}
}

// OwedStage reports the phase Start would enter now and how long it would run
// for, measured against the durations in force now the way NextStage is.
func (t *Timer) OwedStage() (engine.State, time.Duration) {
	t.mu.Lock()
	defer t.mu.Unlock()
	owed := t.engine.OwedPhase()
	return owed, t.phaseDurationLocked(owed)
}

// StartNewCycle abandons the current cycle and begins a fresh work period,
// reporting the engine state as of the moment it did. Reporting from inside
// the lock, the way Stop and Skip do, saves the caller a second, racy read:
// the phase deadline fires from its own goroutine and can otherwise complete
// the phase between a caller's own Snapshot and this call.
func (t *Timer) StartNewCycle() engine.Snapshot {
	t.mu.Lock()
	before := t.engine.Snapshot()
	defer t.notifyChange()
	defer t.mu.Unlock()
	defer t.transitionLocked()
	t.stopTimerLocked()
	t.clearPhaseLocked()
	t.engine.StartNewCycle()
	t.startPhaseTimerLocked(t.workDuration)
	return before
}

func (t *Timer) CompletePeriod() {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.mu.Unlock()
	defer t.transitionLocked()
	t.completePeriodLocked()
}

func (t *Timer) Confirm() {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.mu.Unlock()
	defer t.transitionLocked()
	t.engine.ConfirmNext()
	if d := t.phaseDurationLocked(t.engine.State()); d > 0 {
		t.startPhaseTimerLocked(d)
	}
}

func (t *Timer) SkipToday() {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.mu.Unlock()
	defer t.transitionLocked()
	t.stopTimerLocked()
	t.clearPhaseLocked()
	t.engine.SkipToday()
}

// Pause reports whether the timer was running. A refused pause changes
// nothing, so it does not notify.
func (t *Timer) Pause() bool {
	t.mu.Lock()
	if !t.engine.Pause() {
		t.mu.Unlock()
		return false
	}
	defer t.notifyChange()
	defer t.mu.Unlock()
	defer t.transitionLocked()
	if !t.phaseEndAt.IsZero() {
		t.pausedRemaining = t.phaseEndAt.Sub(t.now())
		if t.pausedRemaining < 0 {
			t.pausedRemaining = 0
		}
	}
	t.pausedElapsed = t.elapsedSincePhaseStartLocked()
	t.stopTimerLocked()
	t.phaseStartedAt = time.Time{}
	t.phaseEndAt = time.Time{}
	t.beginPauseLocked(t.now())
	return true
}

// Resume reports whether a paused phase was restarted. A refused resume
// changes nothing, so it does not notify.
func (t *Timer) Resume() bool {
	t.mu.Lock()
	if !t.engine.Resume() {
		t.mu.Unlock()
		return false
	}
	defer t.notifyChange()
	defer t.mu.Unlock()
	defer t.transitionLocked()
	t.endPauseLocked()
	elapsed := t.pausedElapsed
	d := t.pausedRemaining
	if d <= 0 {
		// pausedRemaining is only ever clamped to zero, never negative, so a
		// zero here means the phase's own duration had already been fully
		// served when Pause observed it — not that nothing is configured.
		// The fallback must still know what was left, which is the current
		// duration minus what pausedElapsed says was already spent.
		total := t.phaseDurationLocked(t.engine.State())
		if total <= 0 {
			return false
		}
		d = total - elapsed
	}
	t.pausedRemaining = 0
	t.pausedElapsed = 0
	if d <= 0 {
		t.completePeriodLocked()
		return true
	}
	t.startPhaseFromLocked(t.now().Add(-elapsed), d)
	return true
}

// Stop suspends the cycle and reports the engine state as of the moment it
// stopped. Reporting from inside the lock, the way Skip does, saves the
// caller a second, racy read: the phase deadline fires from its own
// goroutine and can otherwise complete the phase between a caller's own
// Snapshot and this call, leaving the caller working from a stale state.
func (t *Timer) Stop() engine.Snapshot {
	t.mu.Lock()
	before := t.engine.Snapshot()
	defer t.notifyChange()
	defer t.mu.Unlock()
	defer t.transitionLocked()
	t.stopTimerLocked()
	t.clearPhaseLocked()
	t.engine.Stop()
	return before
}

// Skip ends the running phase now and moves to the next stage's confirmation.
// It reports the phase it ended and whether there was one; a refused skip
// changes nothing, so it does not notify. Reporting the phase from inside the
// lock saves the caller a second, racy read to find out what it skipped.
func (t *Timer) Skip() (engine.State, bool) {
	t.mu.Lock()
	skipped := t.engine.State()
	if !t.engine.SkipPhase() {
		t.mu.Unlock()
		return skipped, false
	}
	defer t.notifyChange()
	defer t.mu.Unlock()
	defer t.transitionLocked()
	t.stopTimerLocked()
	t.clearPhaseLocked()
	return skipped, true
}

func (t *Timer) State() engine.State {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.engine.State()
}

func (t *Timer) NextStage() (engine.State, time.Duration) {
	t.mu.Lock()
	defer t.mu.Unlock()
	next := t.engine.NextPhase()
	return next, t.phaseDurationLocked(next)
}

func (t *Timer) StatusLine() string {
	t.mu.Lock()
	defer t.mu.Unlock()

	state := t.engine.State()
	completedToday := t.engine.CompletedToday()
	workSessionsInBlock := t.engine.WorkSessionsInBlock()
	longBreakEvery := t.engine.LongBreakEvery()
	completedInCycle := workSessionsInBlock % longBreakEvery
	if completedInCycle == 0 && workSessionsInBlock > 0 && (state == engine.AwaitingConfirm || state == engine.LongBreak) {
		completedInCycle = longBreakEvery
	}

	label := t.statusLabelLocked()
	today := fmt.Sprintf("Today: %d", completedToday)
	cycle := fmt.Sprintf("Cycle: %d/%d", completedInCycle, longBreakEvery)

	switch state {
	case engine.Idle, engine.AwaitingConfirm:
		return fmt.Sprintf("%s  %s  %s", label, today, cycle)
	default:
		remaining := "00:00"
		if !t.phaseEndAt.IsZero() {
			remaining = formatRemaining(t.phaseEndAt.Sub(t.now()))
		}
		return fmt.Sprintf("%s  %s  %s  %s", label, remaining, today, cycle)
	}
}

func formatRemaining(d time.Duration) string {
	if d < 0 {
		d = 0
	}
	seconds := int(d.Seconds())
	minutes := seconds / 60
	secs := seconds % 60
	return fmt.Sprintf("%02d:%02d", minutes, secs)
}

// clearPhaseLocked forgets the current phase entirely: nothing is running,
// nothing is paused, and no time has been spent.
func (t *Timer) clearPhaseLocked() {
	t.phaseStartedAt = time.Time{}
	t.phaseEndAt = time.Time{}
	t.pausedRemaining = 0
	t.pausedElapsed = 0
	t.endPauseLocked()
}

// elapsedSincePhaseStartLocked reports how much of the running phase has been
// spent. A phase with no recorded start has spent nothing measurable.
func (t *Timer) elapsedSincePhaseStartLocked() time.Duration {
	if t.phaseStartedAt.IsZero() {
		return 0
	}
	elapsed := t.now().Sub(t.phaseStartedAt)
	if elapsed < 0 {
		return 0
	}
	return elapsed
}

func (t *Timer) completePeriodLocked() {
	t.stopTimerLocked()
	t.phaseStartedAt = time.Time{}
	t.phaseEndAt = time.Time{}
	t.endPauseLocked()
	t.engine.MarkPeriodComplete()
}

// startPhaseTimerLocked runs a phase of length d that begins now.
func (t *Timer) startPhaseTimerLocked(d time.Duration) {
	t.startPhaseFromLocked(t.now(), d)
}

// startPhaseFromLocked runs the remaining d of a phase whose clock began at
// startedAt. Separating the two lets a restored or re-derived phase keep the
// start it really had, so its elapsed time stays true.
func (t *Timer) startPhaseFromLocked(startedAt time.Time, d time.Duration) {
	t.stopTimerLocked()
	t.phaseStartedAt = startedAt
	t.phaseEndAt = t.now().Add(d)
	t.periodTimer = t.after(d, func() {
		t.mu.Lock()
		t.completePeriodLocked()
		t.transitionLocked()
		t.mu.Unlock()
		t.notifyChange()
	})
}

func (t *Timer) stopTimerLocked() {
	if t.periodTimer != nil {
		t.periodTimer.Stop()
		t.periodTimer = nil
	}
}

func (t *Timer) statusLabelLocked() string {
	switch t.engine.State() {
	case engine.Idle:
		return "Idle"
	case engine.Work:
		return "Pomodoro"
	case engine.ShortBreak:
		return "Short break"
	case engine.LongBreak:
		return "Long break"
	case engine.AwaitingConfirm:
		return "Confirm to continue"
	case engine.Paused:
		return "Paused"
	default:
		return "Unknown"
	}
}
