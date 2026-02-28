//go:build integration

package integration_test

import (
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"urgtomat/internal/app"
	"urgtomat/internal/config"
	"urgtomat/internal/scheduler"
)

type fakeNotifier struct {
	calls atomic.Int32
}

func (f *fakeNotifier) PlaySound(string) error {
	f.calls.Add(1)
	return nil
}

func TestCycleTransitionAndReminderAck(t *testing.T) {
	notifier := &fakeNotifier{}
	cycle := app.NewForTest(25, 5, 15, 4, 20*time.Millisecond, notifier)

	cycle.Start()
	cycle.CompletePeriod()
	time.Sleep(70 * time.Millisecond)
	if notifier.calls.Load() == 0 {
		t.Fatal("expected repeating reminders while awaiting confirm")
	}

	cycle.Confirm()
	if got := cycle.Status(); got != "short-break" {
		t.Fatalf("expected short-break after confirm, got %q", got)
	}

	afterConfirm := notifier.calls.Load()
	time.Sleep(60 * time.Millisecond)
	if notifier.calls.Load() != afterConfirm {
		t.Fatal("expected no additional reminders after confirm")
	}
}

func TestConfigToSchedulerTrigger(t *testing.T) {
	cfg, err := config.LoadBytes([]byte(`
schedule_days = ["Mon", "Tue"]
schedule_time = "09:15"
work_minutes = 20
short_break_minutes = 5
long_break_minutes = 10
long_break_every = 4
repeat_secs = 3
`))
	if err != nil {
		t.Fatalf("load config: %v", err)
	}

	s := scheduler.New(cfg.Schedule.Days, cfg.Schedule.Time)
	at := time.Date(2026, 3, 2, 9, 15, 0, 0, time.Local) // Monday
	if !s.ShouldTrigger(at) {
		t.Fatal("expected scheduler trigger from parsed config values")
	}
}

func TestStatusIncludesPomodoroProgress(t *testing.T) {
	notifier := &fakeNotifier{}
	cycle := app.NewForTest(25, 5, 15, 4, 30*time.Millisecond, notifier)
	cycle.Start()

	status := cycle.StatusLine()
	if !strings.Contains(status, "pomodoro 1/4") {
		t.Fatalf("expected pomodoro progress in status line, got %q", status)
	}
}
