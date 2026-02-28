package app

import (
	"context"
	"fmt"
	"os"
	"sync"
	"time"

	"throwntom/internal/engine"
	"throwntom/internal/notifier"
	"throwntom/internal/reminder"
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

func NewForTest(workMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery int, repeatInterval time.Duration, n notifier.Notifier) *App {
	return New(workMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery, repeatInterval, n)
}

func (a *App) Start() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.engine.StartWork()
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

func (a *App) Status() string {
	a.mu.Lock()
	defer a.mu.Unlock()
	switch a.engine.State() {
	case engine.Idle:
		return "idle"
	case engine.Work:
		return "pomodoro"
	case engine.ShortBreak:
		return "short-break"
	case engine.LongBreak:
		return "long-break"
	case engine.AwaitingConfirm:
		return "awaiting confirmation"
	case engine.Paused:
		return "paused"
	default:
		return "unknown"
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
	if state == engine.AwaitingConfirm {
		return fmt.Sprintf("%s | transition pending | today's pomodoros=%d | pomodoros=%d/%d", a.statusLabelLocked(), completedToday, completedInCycle, longBreakEvery)
	}

	remaining := "00:00"
	if !a.phaseEndAt.IsZero() {
		remaining = formatRemaining(time.Until(a.phaseEndAt))
	}
	return fmt.Sprintf("%s | %s | today's pomodoros=%d | pomodoros=%d/%d", a.statusLabelLocked(), remaining, completedToday, completedInCycle, longBreakEvery)
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
		return "idle"
	case engine.Work:
		return "pomodoro"
	case engine.ShortBreak:
		return "short-break"
	case engine.LongBreak:
		return "long-break"
	case engine.AwaitingConfirm:
		return "awaiting-confirm"
	case engine.Paused:
		return "paused"
	default:
		return "unknown"
	}
}
