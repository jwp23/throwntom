package pomodoro

import (
	"context"
	"fmt"
	"os"
	"sync"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/notifier"
	"github.com/jwp23/throwntom/v3/internal/reminder"
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
	notifier           notifier.Notifier
	reminderPolicy     reminder.Policy
	workDuration       time.Duration
	shortBreakDuration time.Duration
	longBreakDuration  time.Duration
	now                func() time.Time
	after              afterFunc
	reminderCancel     context.CancelFunc
	periodTimer        stopper
	phaseEndAt         time.Time
	pausedRemaining    time.Duration
	onChange           func()
	// onTransition runs inside the Timer lock, before the verb returns, every
	// time the engine's state is set: by a verb, by a countdown ending or by
	// Restore. It must not call back into the Timer.
	onTransition func(to engine.State)
}

func New(workMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery int, reminderPolicy reminder.Policy, n notifier.Notifier) *Timer {
	return &Timer{
		engine:             engine.New(workMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery),
		notifier:           n,
		reminderPolicy:     reminderPolicy,
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
	PhaseEndAt      time.Time       `json:"phase_end_at"`
	PausedRemaining time.Duration   `json:"paused_remaining"`
}

func (t *Timer) Snapshot() Snapshot {
	t.mu.Lock()
	defer t.mu.Unlock()
	return Snapshot{
		Engine:          t.engine.Snapshot(),
		PhaseEndAt:      t.phaseEndAt,
		PausedRemaining: t.pausedRemaining,
	}
}

func (t *Timer) Restore(s Snapshot, now time.Time) error {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.transitionLocked()
	defer t.mu.Unlock()
	t.engine.Restore(s.Engine)

	switch s.Engine.State {
	case engine.Work, engine.ShortBreak, engine.LongBreak:
		remaining := s.PhaseEndAt.Sub(now)
		if remaining > 0 {
			t.startPhaseTimerLocked(remaining)
		} else {
			t.completePeriodLocked()
		}
	case engine.Paused:
		t.pausedRemaining = s.PausedRemaining
	case engine.AwaitingConfirm:
		t.startReminderLocked()
	}
	return nil
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

func (t *Timer) Start() {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.transitionLocked()
	defer t.mu.Unlock()
	t.engine.StartWork()
	t.startPhaseTimerLocked(t.workDuration)
}

func (t *Timer) StartNewCycle() {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.transitionLocked()
	defer t.mu.Unlock()
	t.stopReminderLocked()
	t.stopTimerLocked()
	t.phaseEndAt = time.Time{}
	t.pausedRemaining = 0
	t.engine.StartNewCycle()
	t.startPhaseTimerLocked(t.workDuration)
}

func (t *Timer) CompletePeriod() {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.transitionLocked()
	defer t.mu.Unlock()
	t.completePeriodLocked()
}

func (t *Timer) Confirm() {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.transitionLocked()
	defer t.mu.Unlock()
	t.stopReminderLocked()
	t.engine.ConfirmNext()
	switch t.engine.State() {
	case engine.Work:
		t.startPhaseTimerLocked(t.workDuration)
	case engine.ShortBreak:
		t.startPhaseTimerLocked(t.shortBreakDuration)
	case engine.LongBreak:
		t.startPhaseTimerLocked(t.longBreakDuration)
	}
}

func (t *Timer) Snooze(d time.Duration) {
	t.mu.Lock()
	defer t.notifyChange()
	t.stopReminderLocked()
	state := t.engine.State()
	after := t.after
	t.mu.Unlock()

	if state != engine.AwaitingConfirm {
		return
	}

	after(d, func() {
		t.mu.Lock()
		defer t.mu.Unlock()
		if t.engine.State() == engine.AwaitingConfirm {
			t.startReminderLocked()
		}
	})
}

func (t *Timer) SkipToday() {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.transitionLocked()
	defer t.mu.Unlock()
	t.stopReminderLocked()
	t.stopTimerLocked()
	t.phaseEndAt = time.Time{}
	t.pausedRemaining = 0
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
	defer t.transitionLocked()
	defer t.mu.Unlock()
	if !t.phaseEndAt.IsZero() {
		t.pausedRemaining = t.phaseEndAt.Sub(t.now())
		if t.pausedRemaining < 0 {
			t.pausedRemaining = 0
		}
	}
	t.stopTimerLocked()
	t.phaseEndAt = time.Time{}
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
	defer t.transitionLocked()
	defer t.mu.Unlock()
	d := t.pausedRemaining
	if d <= 0 {
		switch t.engine.State() {
		case engine.Work:
			d = t.workDuration
		case engine.ShortBreak:
			d = t.shortBreakDuration
		case engine.LongBreak:
			d = t.longBreakDuration
		default:
			return false
		}
	}
	t.pausedRemaining = 0
	t.startPhaseTimerLocked(d)
	return true
}

func (t *Timer) Stop() {
	t.mu.Lock()
	defer t.notifyChange()
	defer t.transitionLocked()
	defer t.mu.Unlock()
	t.stopReminderLocked()
	t.stopTimerLocked()
	t.phaseEndAt = time.Time{}
	t.pausedRemaining = 0
	t.engine.Stop()
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
	switch next {
	case engine.Work:
		return next, t.workDuration
	case engine.ShortBreak:
		return next, t.shortBreakDuration
	case engine.LongBreak:
		return next, t.longBreakDuration
	default:
		return next, 0
	}
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

func (t *Timer) completePeriodLocked() {
	t.stopTimerLocked()
	t.phaseEndAt = time.Time{}
	t.engine.MarkPeriodComplete()
	if t.engine.State() == engine.AwaitingConfirm {
		t.startReminderLocked()
	}
}

func (t *Timer) startReminderLocked() {
	t.stopReminderLocked()
	ctx, cancel := context.WithCancel(context.Background())
	t.reminderCancel = cancel
	n := t.notifier
	loop := reminder.New(t.reminderPolicy, func() error {
		if err := n.PlaySound("default"); err != nil {
			_, _ = os.Stdout.WriteString("\a")
			return fmt.Errorf("notifier failure: %w", err)
		}
		return nil
	})
	go loop.Run(ctx)
}

func (t *Timer) stopReminderLocked() {
	if t.reminderCancel != nil {
		t.reminderCancel()
		t.reminderCancel = nil
	}
}

func (t *Timer) startPhaseTimerLocked(d time.Duration) {
	t.stopTimerLocked()
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
