package core

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/reminder"
)

func TestApplyConfigRederivesRunningPhase(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()
	c.execute(cmdStart)

	cfg.Pomodoro.WorkMinutes = 50
	c.ApplyConfig(cfg)

	state := c.State()
	if state.State != engine.Work {
		t.Fatalf("expected work to continue, got %s", state.State)
	}
	remaining := time.Until(*state.PhaseEndAt)
	if remaining < 49*time.Minute || remaining > 50*time.Minute {
		t.Fatalf("expected roughly 50m remaining, got %s", remaining)
	}
}

func TestApplyConfigShorterThanElapsedEndsPhase(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()
	c.execute(cmdStart)
	// Pretend the phase started an hour ago by moving the clock forward.
	c.setNow(func() time.Time { return time.Now().Add(time.Hour) })

	cfg.Pomodoro.WorkMinutes = 25
	c.ApplyConfig(cfg)

	if got := c.State().State; got != engine.AwaitingConfirm {
		t.Fatalf("expected an already-elapsed phase to end, got %s", got)
	}
}

func TestApplyConfigUpdatesLongBreakEvery(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()

	cfg.Pomodoro.LongBreakEvery = 2
	c.ApplyConfig(cfg)

	if got := c.State().LongBreakEvery; got != 2 {
		t.Fatalf("expected long_break_every 2 in published state, got %d", got)
	}
}

func TestApplyConfigUpdatesReminderPolicy(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()

	cfg.RepeatSecs = 45
	cfg.RepeatLimitSecs = 600
	c.ApplyConfig(cfg)

	c.reminder.mu.Lock()
	policy := c.reminder.policy
	c.reminder.mu.Unlock()
	want := reminder.NewPolicy(45*time.Second, 600*time.Second)
	if policy != want {
		t.Fatalf("expected policy %+v, got %+v", want, policy)
	}
}

func TestApplyConfigUpdatesSchedule(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()

	cfg.Schedule = []config.ScheduleEntry{{
		Days: []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"},
		Time: "06:30",
	}}
	c.ApplyConfig(cfg)

	// 07:00 on a Sunday is after 06:30 on every day of the new schedule and
	// before the 09:15 weekday-only default.
	sunday := time.Date(2026, 8, 30, 7, 0, 0, 0, time.UTC)
	c.mu.Lock()
	active := c.scheduler.IsActiveNow(sunday)
	c.mu.Unlock()
	if !active {
		t.Fatal("expected the reloaded schedule to be active")
	}
}

func TestApplyConfigPublishesState(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()
	c.execute(cmdStart)

	ch := make(chan State)
	unsubscribe := c.subscribeSync(ch)
	defer unsubscribe()

	cfg.Pomodoro.WorkMinutes = 50
	go c.ApplyConfig(cfg)

	select {
	case <-ch:
	case <-time.After(time.Second):
		t.Fatal("expected a published state after config reload")
	}
}
