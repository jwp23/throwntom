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

type App struct {
	mu                 sync.Mutex
	engine             *engine.Engine
	notifier           notifier.Notifier
	repeatInterval     time.Duration
	workDuration       time.Duration
	shortBreakDuration time.Duration
	longBreakDuration  time.Duration
	reminderCancel     context.CancelFunc
	periodTimer        *time.Timer
	phaseEndAt         time.Time
	pausedRemaining    time.Duration
}

func New(workMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery int, repeatInterval time.Duration, n notifier.Notifier) *App {
	return &App{
		engine:             engine.New(workMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery),
		notifier:           n,
		repeatInterval:     repeatInterval,
		workDuration:       time.Duration(workMinutes) * time.Minute,
		shortBreakDuration: time.Duration(shortBreakMinutes) * time.Minute,
		longBreakDuration:  time.Duration(longBreakMinutes) * time.Minute,
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

func (a *App) Restore(s Snapshot) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.engine.Restore(s.Engine)

	switch s.Engine.State {
	case engine.Work, engine.ShortBreak, engine.LongBreak:
		remaining := time.Until(s.PhaseEndAt)
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
	defer a.mu.Unlock()
	a.engine.AdvanceDay(now)
}

func (a *App) Start() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.engine.StartWork()
	a.startPhaseTimerLocked(a.workDuration)
}

func (a *App) StartNewCycle() {
	a.mu.Lock()
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
	defer a.mu.Unlock()
	a.completePeriodLocked()
}

func (a *App) Confirm() {
	a.mu.Lock()
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
	a.engine.Snooze(d)
	a.stopReminderLocked()
	state := a.engine.State()
	a.mu.Unlock()

	if state != engine.AwaitingConfirm {
		return
	}

	go func() {
		time.Sleep(d)
		a.mu.Lock()
		defer a.mu.Unlock()
		if a.engine.State() == engine.AwaitingConfirm {
			a.startReminderLocked()
		}
	}()
}

func (a *App) SkipToday() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.stopReminderLocked()
	a.stopTimerLocked()
	a.phaseEndAt = time.Time{}
	a.pausedRemaining = 0
	a.engine.SkipToday()
}

func (a *App) Pause() {
	a.mu.Lock()
	defer a.mu.Unlock()
	if !a.engine.Pause() {
		return
	}
	if !a.phaseEndAt.IsZero() {
		a.pausedRemaining = time.Until(a.phaseEndAt)
		if a.pausedRemaining < 0 {
			a.pausedRemaining = 0
		}
	}
	a.stopTimerLocked()
	a.phaseEndAt = time.Time{}
}

func (a *App) Resume() {
	a.mu.Lock()
	defer a.mu.Unlock()
	if !a.engine.Resume() {
		return
	}
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
			return
		}
	}
	a.pausedRemaining = 0
	a.startPhaseTimerLocked(d)
}

func (a *App) Stop() {
	a.mu.Lock()
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
			remaining = formatRemaining(time.Until(a.phaseEndAt))
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

func (a *App) startReminderLocked() {
	a.stopReminderLocked()
	ctx, cancel := context.WithCancel(context.Background())
	a.reminderCancel = cancel
	loop := reminder.New(a.repeatInterval, func() error {
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
	}
}

func (a *App) startPhaseTimerLocked(d time.Duration) {
	a.stopTimerLocked()
	a.phaseEndAt = time.Now().Add(d)
	a.periodTimer = time.AfterFunc(d, func() {
		a.mu.Lock()
		defer a.mu.Unlock()
		a.completePeriodLocked()
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
