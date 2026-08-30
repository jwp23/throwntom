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

// Shortening the running phase past the time it has already spent ends it;
// that boundary is pinned in internal/pomodoro, which can drive the timer's
// clock. Here the question is only that a shorter duration reaches the
// running phase at all.
func TestApplyConfigShortensRunningPhase(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()
	c.execute(cmdStart)

	cfg.Pomodoro.WorkMinutes = 1
	c.ApplyConfig(cfg)

	state := c.State()
	if state.State != engine.Work {
		t.Fatalf("expected work to continue, got %s", state.State)
	}
	if remaining := time.Until(*state.PhaseEndAt); remaining > time.Minute {
		t.Fatalf("expected at most a minute left of the new 1m phase, got %s", remaining)
	}
}

// A reload must not answer a reminder the user has not: the morning nudge
// only fires once a day, so cancelling it on a config edit loses it for good.
func TestApplyConfigLeavesAnOutstandingReminderRinging(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()
	c.reminder.raise(reminderMorning)

	cfg.Pomodoro.WorkMinutes = 50
	c.ApplyConfig(cfg)

	if got := c.reminder.outstanding(); got != reminderMorning {
		t.Fatalf("expected the morning reminder to survive a reload, got %v", got)
	}
}

func TestApplyConfigOnAStoppedCoreDoesNothing(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdStart)
	before := c.State()
	c.Stop()

	cfg.Pomodoro.WorkMinutes = 50
	c.ApplyConfig(cfg)

	after := c.State()
	if !after.PhaseEndAt.Equal(*before.PhaseEndAt) {
		t.Fatalf("expected a stopped core to ignore the reload, phase end moved %s → %s",
			before.PhaseEndAt, after.PhaseEndAt)
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

// The setting only ever reaches the user through a client reading state, so a
// reload that did not republish it would leave the edit invisible until the
// next daemon restart.
func TestApplyConfigUpdatesFloatWindowWhenWaiting(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()

	cfg.FloatWindowWhenWaiting = true
	c.ApplyConfig(cfg)

	if !c.State().FloatWindowWhenWaiting {
		t.Fatal("expected float_window_when_waiting true in published state")
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

	states, unsubscribe := c.Subscribe()
	defer unsubscribe()
	<-states // the State every subscriber is seeded with

	cfg.Pomodoro.WorkMinutes = 50
	c.ApplyConfig(cfg)

	select {
	case state := <-states:
		if state.PhaseEndAt == nil || time.Until(*state.PhaseEndAt) < 49*time.Minute {
			t.Fatalf("expected the published state to carry the new phase end, got %+v", state)
		}
	case <-time.After(time.Second):
		t.Fatal("expected a published state after config reload")
	}
}
