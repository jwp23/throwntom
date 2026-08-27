package app

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

// timer cancels a callback scheduled with afterFunc.
type timer interface {
	Stop() bool
}

// afterFunc schedules fn to run once after d and returns a handle to cancel
// it. It is the only way App schedules work in the future, so a test clock can
// replace both it and App's now to make timer-driven behavior deterministic.
type afterFunc func(d time.Duration, fn func()) timer

func realAfterFunc(d time.Duration, fn func()) timer {
	return time.AfterFunc(d, fn)
}

type App struct {
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
	periodTimer        timer
	phaseEndAt         time.Time
	pausedRemaining    time.Duration
	onChange           func()
}

func New(workMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery int, reminderPolicy reminder.Policy, n notifier.Notifier) *App {
	return &App{
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
// timer-driven ones. fn runs outside the App lock.
func (a *App) SetOnChange(fn func()) {
	a.mu.Lock()
	a.onChange = fn
	a.mu.Unlock()
}

func (a *App) notifyChange() {
	a.mu.Lock()
	fn := a.onChange
	a.mu.Unlock()
	if fn != nil {
		fn()
	}
}

type Snapshot struct {
	Engine          engine.Snapshot `json:"engine"`
	PhaseEndAt      time.Time       `json:"phase_end_at"`
	PausedRemaining time.Duration   `json:"paused_remaining"`
}

func (a *App) Snapshot() Snapshot {
	a.mu.Lock()
	defer a.mu.Unlock()
	return Snapshot{
		Engine:          a.engine.Snapshot(),
		PhaseEndAt:      a.phaseEndAt,
		PausedRemaining: a.pausedRemaining,
	}
}

func (a *App) Restore(s Snapshot, now time.Time) error {
	a.mu.Lock()
	defer a.notifyChange()
	defer a.mu.Unlock()
	a.engine.Restore(s.Engine)

	switch s.Engine.State {
	case engine.Work, engine.ShortBreak, engine.LongBreak:
		remaining := s.PhaseEndAt.Sub(now)
		if remaining > 0 {
			a.startPhaseTimerLocked(remaining)
		} else {
			a.completePeriodLocked()
		}
	case engine.Paused:
		a.pausedRemaining = s.PausedRemaining
	case engine.AwaitingConfirm:
		a.startReminderLocked()
	}
	return nil
}

func (a *App) AdvanceDay(now time.Time) {
	a.mu.Lock()
	before := a.engine.Snapshot()
	a.engine.AdvanceDay(now)
	after := a.engine.Snapshot()
	a.mu.Unlock()
	if dayRolledOver(before, after) {
		a.notifyChange()
	}
}

// dayRolledOver reports whether AdvanceDay started a new work day and reset the
// day's counters. Recording the very first work date is not a rollover: nothing
// an observer can see changes, and notifying on it would make every status read
// look like a state change.
func dayRolledOver(before, after engine.Snapshot) bool {
	return !before.WorkDate.IsZero() && !engine.IsSameDay(before.WorkDate, after.WorkDate)
}

func (a *App) Start() {
	a.mu.Lock()
	defer a.notifyChange()
	defer a.mu.Unlock()
	a.engine.StartWork()
	a.startPhaseTimerLocked(a.workDuration)
}

func (a *App) StartNewCycle() {
	a.mu.Lock()
	defer a.notifyChange()
	defer a.mu.Unlock()
	a.stopReminderLocked()
	a.stopTimerLocked()
	a.phaseEndAt = time.Time{}
	a.pausedRemaining = 0
	a.engine.StartNewCycle()
	a.startPhaseTimerLocked(a.workDuration)
}

func (a *App) CompletePeriod() {
	a.mu.Lock()
	defer a.notifyChange()
	defer a.mu.Unlock()
	a.completePeriodLocked()
}

func (a *App) Confirm() {
	a.mu.Lock()
	defer a.notifyChange()
	defer a.mu.Unlock()
	a.stopReminderLocked()
	a.engine.ConfirmNext()
	switch a.engine.State() {
	case engine.Work:
		a.startPhaseTimerLocked(a.workDuration)
	case engine.ShortBreak:
		a.startPhaseTimerLocked(a.shortBreakDuration)
	case engine.LongBreak:
		a.startPhaseTimerLocked(a.longBreakDuration)
	}
}

func (a *App) Snooze(d time.Duration) {
	a.mu.Lock()
	defer a.notifyChange()
	a.stopReminderLocked()
	state := a.engine.State()
	after := a.after
	a.mu.Unlock()

	if state != engine.AwaitingConfirm {
		return
	}

	after(d, func() {
		a.mu.Lock()
		defer a.mu.Unlock()
		if a.engine.State() == engine.AwaitingConfirm {
			a.startReminderLocked()
		}
	})
}

func (a *App) SkipToday() {
	a.mu.Lock()
	defer a.notifyChange()
	defer a.mu.Unlock()
	a.stopReminderLocked()
	a.stopTimerLocked()
	a.phaseEndAt = time.Time{}
	a.pausedRemaining = 0
	a.engine.SkipToday()
}

// Pause reports whether the timer was running. A refused pause changes
// nothing, so it does not notify.
func (a *App) Pause() bool {
	a.mu.Lock()
	if !a.engine.Pause() {
		a.mu.Unlock()
		return false
	}
	defer a.notifyChange()
	defer a.mu.Unlock()
	if !a.phaseEndAt.IsZero() {
		a.pausedRemaining = a.phaseEndAt.Sub(a.now())
		if a.pausedRemaining < 0 {
			a.pausedRemaining = 0
		}
	}
	a.stopTimerLocked()
	a.phaseEndAt = time.Time{}
	return true
}

// Resume reports whether a paused phase was restarted. A refused resume
// changes nothing, so it does not notify.
func (a *App) Resume() bool {
	a.mu.Lock()
	if !a.engine.Resume() {
		a.mu.Unlock()
		return false
	}
	defer a.notifyChange()
	defer a.mu.Unlock()
	d := a.pausedRemaining
	if d <= 0 {
		switch a.engine.State() {
		case engine.Work:
			d = a.workDuration
		case engine.ShortBreak:
			d = a.shortBreakDuration
		case engine.LongBreak:
			d = a.longBreakDuration
		default:
			return false
		}
	}
	a.pausedRemaining = 0
	a.startPhaseTimerLocked(d)
	return true
}

func (a *App) Stop() {
	a.mu.Lock()
	defer a.notifyChange()
	defer a.mu.Unlock()
	a.stopReminderLocked()
	a.stopTimerLocked()
	a.phaseEndAt = time.Time{}
	a.pausedRemaining = 0
	a.engine.Stop()
}

func (a *App) State() engine.State {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.engine.State()
}

func (a *App) NextStage() (engine.State, time.Duration) {
	a.mu.Lock()
	defer a.mu.Unlock()
	next := a.engine.NextPhase()
	switch next {
	case engine.Work:
		return next, a.workDuration
	case engine.ShortBreak:
		return next, a.shortBreakDuration
	case engine.LongBreak:
		return next, a.longBreakDuration
	default:
		return next, 0
	}
}

func (a *App) StatusLine() string {
	a.mu.Lock()
	defer a.mu.Unlock()

	state := a.engine.State()
	completedToday := a.engine.CompletedToday()
	workSessionsInBlock := a.engine.WorkSessionsInBlock()
	longBreakEvery := a.engine.LongBreakEvery()
	completedInCycle := workSessionsInBlock % longBreakEvery
	if completedInCycle == 0 && workSessionsInBlock > 0 && (state == engine.AwaitingConfirm || state == engine.LongBreak) {
		completedInCycle = longBreakEvery
	}

	label := a.statusLabelLocked()
	today := fmt.Sprintf("Today: %d", completedToday)
	cycle := fmt.Sprintf("Cycle: %d/%d", completedInCycle, longBreakEvery)

	switch state {
	case engine.Idle, engine.AwaitingConfirm:
		return fmt.Sprintf("%s  %s  %s", label, today, cycle)
	default:
		remaining := "00:00"
		if !a.phaseEndAt.IsZero() {
			remaining = formatRemaining(a.phaseEndAt.Sub(a.now()))
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

func (a *App) completePeriodLocked() {
	a.stopTimerLocked()
	a.phaseEndAt = time.Time{}
	a.engine.MarkPeriodComplete()
	if a.engine.State() == engine.AwaitingConfirm {
		a.startReminderLocked()
	}
}

// reminderTitle heads the actionable alert; the body says which phase is waiting.
const reminderTitle = "Throwntom"

func (a *App) startReminderLocked() {
	a.stopReminderLocked()
	ctx, cancel := context.WithCancel(context.Background())
	a.reminderCancel = cancel
	// Best effort: the repeating sound is the reminder itself, the alert is
	// only how the user answers it without the menu bar app.
	_ = a.notifier.ShowReminder(reminderTitle, a.reminderBodyLocked())
	loop := reminder.New(a.reminderPolicy, func() error {
		if err := a.notifier.PlaySound("default"); err != nil {
			_, _ = os.Stdout.WriteString("\a")
			return fmt.Errorf("notifier failure: %w", err)
		}
		return nil
	})
	go loop.Run(ctx)
}

func (a *App) stopReminderLocked() {
	if a.reminderCancel != nil {
		a.reminderCancel()
		a.reminderCancel = nil
		_ = a.notifier.ClearReminder()
	}
}

func (a *App) reminderBodyLocked() string {
	switch a.engine.NextPhase() {
	case engine.Work:
		return "Ready to start a pomodoro"
	case engine.ShortBreak:
		return "Ready for a short break"
	case engine.LongBreak:
		return "Ready for a long break"
	default:
		return "Confirm to continue"
	}
}

func (a *App) startPhaseTimerLocked(d time.Duration) {
	a.stopTimerLocked()
	a.phaseEndAt = a.now().Add(d)
	a.periodTimer = a.after(d, func() {
		a.mu.Lock()
		a.completePeriodLocked()
		a.mu.Unlock()
		a.notifyChange()
	})
}

func (a *App) stopTimerLocked() {
	if a.periodTimer != nil {
		a.periodTimer.Stop()
		a.periodTimer = nil
	}
}

func (a *App) statusLabelLocked() string {
	switch a.engine.State() {
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
