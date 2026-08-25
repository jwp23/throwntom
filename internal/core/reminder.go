package core

import (
	"context"
	"sync"
	"time"

	"github.com/jwp23/throwntom/v3/internal/app"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/notifier"
	"github.com/jwp23/throwntom/v3/internal/reminder"
	"github.com/jwp23/throwntom/v3/internal/scheduler"
)

type reminderState struct {
	mu             sync.Mutex
	morningCancel  context.CancelFunc
	snoozeUntil    time.Time
	lastTriggerDay string
	morningPending bool
}

func (s *reminderState) statusSnapshot(cycle *app.App) (string, engine.State, bool) {
	s.mu.Lock()
	currentMorningPending := s.morningPending
	s.mu.Unlock()
	return cycle.StatusLine(), cycle.State(), currentMorningPending
}

func (s *reminderState) beginMorningLoop() (context.Context, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.morningCancel != nil {
		return nil, false
	}
	ctx, cancel := context.WithCancel(context.Background())
	s.morningPending = true
	s.morningCancel = cancel
	return ctx, true
}

func (s *reminderState) stopMorningLoop() {
	s.mu.Lock()
	cancel := s.morningCancel
	s.morningCancel = nil
	s.morningPending = false
	s.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func (s *reminderState) shouldStartMorning(now time.Time, sched *scheduler.Scheduler) bool {
	dayKey := now.Format("2006-01-02")
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.snoozeUntil.IsZero() && now.Before(s.snoozeUntil) {
		return false
	}
	if !sched.ShouldTrigger(now) || dayKey == s.lastTriggerDay {
		return false
	}
	s.lastTriggerDay = dayKey
	return true
}

func (s *reminderState) clearSnooze() {
	s.mu.Lock()
	s.snoozeUntil = time.Time{}
	s.mu.Unlock()
}

func (s *reminderState) setSnoozeUntil(until time.Time) {
	s.mu.Lock()
	s.snoozeUntil = until
	s.mu.Unlock()
}

func (s *reminderState) markSkippedToday(now time.Time) {
	s.mu.Lock()
	s.snoozeUntil = time.Time{}
	s.lastTriggerDay = now.Format("2006-01-02")
	s.mu.Unlock()
}

func (s *reminderState) isMorningPending() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.morningPending
}

func (s *reminderState) snoozeDeadline() (time.Time, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.snoozeUntil, !s.snoozeUntil.IsZero()
}

func startMorningLoop(state *reminderState, repeatInterval time.Duration, n notifier.Notifier) {
	ctx, shouldStart := state.beginMorningLoop()
	if !shouldStart {
		return
	}
	loop := reminder.New(repeatInterval, func() error {
		return n.PlaySound("morning")
	})
	go loop.Run(ctx)
}

func startMorningScheduler(ctx context.Context, state *reminderState, sched *scheduler.Scheduler, repeatInterval time.Duration, n notifier.Notifier) {
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case now := <-ticker.C:
				if !state.shouldStartMorning(now, sched) {
					continue
				}
				startMorningLoop(state, repeatInterval, n)
			}
		}
	}()
}
