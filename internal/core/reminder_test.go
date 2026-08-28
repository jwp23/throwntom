package core

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/reminder"
)

// mondayAt returns a clock set to Monday 2 March 2026 at the given hour, on
// either side of the default 09:15 schedule.
func mondayAt(hour, minute int) *fakeClock {
	return newFakeClock(time.Date(2026, 3, 2, hour, minute, 0, 0, time.Local))
}

func startedCore(t *testing.T, cfg config.Config, clk *fakeClock) *Core {
	t.Helper()
	c := newCore(cfg, noopNotifier{})
	c.setClock(clk)
	ctx, cancel := context.WithCancel(context.Background())
	c.Start(ctx)
	t.Cleanup(func() { cancel(); c.Stop() })
	return c
}

func TestStartRaisesMorningWhenPendingAndIdle(t *testing.T) {
	c := startedCore(t, config.Default(), mondayAt(10, 0))
	if c.reminder.outstanding() != reminderMorning {
		t.Fatal("expected morning reminder after start with morningPending=true and idle timer")
	}
}

func TestStartSkipsMorningWhenNotPending(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := startedCore(t, cfg, mondayAt(10, 0))
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected no reminder when morningPending=false")
	}
}

func TestStartSkipsMorningWhenTimerNotIdle(t *testing.T) {
	c := newCore(config.Default(), noopNotifier{})
	c.setClock(mondayAt(10, 0))
	c.execute(cmdStart)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c.Start(ctx)
	defer c.Stop()
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected no morning reminder when timer is not idle")
	}
}

func TestStartSkipsMorningBeforeScheduledTime(t *testing.T) {
	c := startedCore(t, config.Default(), mondayAt(8, 0))
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected no morning reminder before scheduled time")
	}
}

func TestMorningSnoozeKeepsPendingAndResumesAtDeadline(t *testing.T) {
	clk := mondayAt(10, 0)
	c := startedCore(t, config.Default(), clk)
	result := c.execute("snooze 10m")
	if result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}
	if !strings.Contains(result.message, "morning reminder snoozed") {
		t.Fatalf("expected morning snooze message, got %q", result.message)
	}
	_, _, pending := c.Status()
	if !pending {
		t.Fatal("expected morning_pending to stay true during a snooze")
	}
	if until, ok := c.reminder.snoozeDeadline(); !ok || !until.Equal(clk.Now().Add(10*time.Minute)) {
		t.Fatalf("expected deadline 10m ahead, got %v %v", until, ok)
	}
	clk.Advance(10 * time.Minute)
	if _, ok := c.reminder.snoozeDeadline(); ok {
		t.Fatal("expected snooze cleared at its deadline")
	}
	if c.reminder.outstanding() != reminderMorning {
		t.Fatal("expected morning reminder still outstanding after resume")
	}
}

func TestStartDuringMorningSnoozeCancelsIt(t *testing.T) {
	clk := mondayAt(10, 0)
	c := startedCore(t, config.Default(), clk)
	if result := c.execute("snooze 10m"); result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}
	c.execute(cmdStart)
	clk.Advance(10 * time.Minute)
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected no reminder after start during a snooze")
	}
	if _, ok := c.reminder.snoozeDeadline(); ok {
		t.Fatal("expected deadline cleared by start")
	}
}

func TestSnoozeWithNothingOutstandingIsRefused(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := startedCore(t, cfg, mondayAt(10, 0))
	result := c.execute("snooze 5m")
	if !errors.Is(result.err, errNoReminder) {
		t.Fatalf("expected errNoReminder, got %v", result.err)
	}
	if classifyError(result.err) != ErrorRefused {
		t.Fatal("expected a refusal, not a usage error")
	}
}

func TestSnoozeRejectsNonPositiveDuration(t *testing.T) {
	c := startedCore(t, config.Default(), mondayAt(10, 0))
	for _, arg := range []string{"0", "-5m"} {
		result := c.execute("snooze " + arg)
		if result.err == nil || classifyError(result.err) != ErrorUsage {
			t.Fatalf("snooze %s: expected usage error, got %v", arg, result.err)
		}
	}
}

func TestSkipTodayCancelsMorningReminder(t *testing.T) {
	c := startedCore(t, config.Default(), mondayAt(10, 0))
	c.execute("skip-today")
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected skip-today to cancel the morning reminder")
	}
	_, _, pending := c.Status()
	if pending {
		t.Fatal("expected morning_pending false after skip-today")
	}
}

func TestScheduleTickRaisesMorningOnce(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.setClock(mondayAt(9, 15))
	c.tickMorning()
	if c.reminder.outstanding() != reminderMorning {
		t.Fatal("expected the schedule tick to raise the morning reminder")
	}
	c.reminder.cancel()
	c.tickMorning()
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected the schedule not to fire twice in one day")
	}
}

func TestScheduleTickIgnoresBusyTimer(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.setClock(mondayAt(9, 15))
	c.execute(cmdStart)
	c.tickMorning()
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected no morning reminder while a pomodoro runs")
	}
	c.timer.Stop()
}

func TestMorningReminderPolicyComesFromConfig(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.RepeatSecs = 30
	cfg.RepeatLimitSecs = 120
	c := newCore(cfg, noopNotifier{})
	want := reminder.Policy{Interval: 30 * time.Second, MaxAlerts: 5}
	if c.reminder.policy != want {
		t.Fatalf("expected %+v, got %+v", want, c.reminder.policy)
	}
}
