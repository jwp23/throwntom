//go:build integration

package integration_test

import (
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/app"
	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/scheduler"
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
	cycle := app.New(25, 5, 15, 4, 20*time.Millisecond, notifier)

	cycle.Start()
	cycle.CompletePeriod()
	time.Sleep(70 * time.Millisecond)
	if notifier.calls.Load() == 0 {
		t.Fatal("expected repeating reminders while awaiting confirm")
	}

	cycle.Confirm()
	if got := cycle.State(); got != engine.ShortBreak {
		t.Fatalf("expected ShortBreak after confirm, got %q", got)
	}

	afterConfirm := notifier.calls.Load()
	time.Sleep(60 * time.Millisecond)
	if notifier.calls.Load() != afterConfirm {
		t.Fatal("expected no additional reminders after confirm")
	}
}

func TestConfigToSchedulerTrigger(t *testing.T) {
	cfg, err := config.LoadBytes([]byte(`
repeat_secs = 3

[pomodoro]
work_minutes = 20
short_break_minutes = 5
long_break_minutes = 10
long_break_every = 4

[[schedule]]
days = ["Mon", "Tue"]
time = "09:15"
`))
	if err != nil {
		t.Fatalf("load config: %v", err)
	}

	s := scheduler.New(config.ScheduleDayTimes(cfg.Schedule))
	if !s.ShouldTrigger(time.Date(2026, 3, 2, 9, 15, 0, 0, time.Local)) { // Monday
		t.Fatal("expected scheduler trigger from parsed config values")
	}
}

func TestStatusIncludesPomodoroProgress(t *testing.T) {
	notifier := &fakeNotifier{}
	cycle := app.New(25, 5, 15, 4, 30*time.Millisecond, notifier)
	cycle.Start()

	if status := cycle.StatusLine(); !strings.Contains(status, "Cycle: 0/4") {
		t.Fatalf("expected pomodoro progress in status line, got %q", status)
	}
}
