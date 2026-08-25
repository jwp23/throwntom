package core

import (
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

func TestEmptyInputInAwaitingConfirmAdvances(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdStart)
	c.cycle.CompletePeriod()
	if c.cycle.State() != engine.AwaitingConfirm {
		t.Fatalf("precondition: expected AwaitingConfirm, got %s", c.cycle.State())
	}

	c.execute("")

	if c.cycle.State() == engine.AwaitingConfirm {
		t.Fatalf("expected empty input to advance out of AwaitingConfirm")
	}
	if c.cycle.State() != engine.ShortBreak {
		t.Fatalf("expected ShortBreak after confirm, got %s", c.cycle.State())
	}
}

func TestEmptyInputOutsideAwaitingConfirmIsNoop(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})

	before := c.cycle.State()
	result := c.execute("")
	if result.err != nil {
		t.Fatalf("unexpected error on empty input: %v", result.err)
	}
	if c.cycle.State() != before {
		t.Fatalf("empty input should not change state, got %s → %s", before, c.cycle.State())
	}

	c.execute(cmdStart)
	workBefore := c.cycle.State()
	c.execute("")
	if c.cycle.State() != workBefore {
		t.Fatalf("empty input during work should not change state, got %s → %s", workBefore, c.cycle.State())
	}
}

func TestTypedConfirmStillAdvances(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdStart)
	c.cycle.CompletePeriod()

	c.execute("confirm")

	if c.cycle.State() != engine.ShortBreak {
		t.Fatalf("expected ShortBreak after typed confirm, got %s", c.cycle.State())
	}
}

func TestNewCycleCommandResetsCycleProgressButKeepsDailyTotal(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})

	c.execute(cmdStart)
	c.cycle.CompletePeriod()
	before, _, _ := c.Status()
	if !strings.Contains(before, statusTodayPomodoros1) {
		t.Fatalf("expected baseline daily total, got %s", before)
	}

	result := c.execute("new-cycle")
	if result.err != nil {
		t.Fatalf("new-cycle command failed: %v", result.err)
	}

	after, _, _ := c.Status()
	if !strings.Contains(after, "Pomodoro") {
		t.Fatalf("expected Pomodoro state, got %s", after)
	}
	if !strings.Contains(after, "Cycle: 0/4") {
		t.Fatalf("expected cycle reset, got %s", after)
	}
	if !strings.Contains(after, statusTodayPomodoros1) {
		t.Fatalf("expected daily total preserved, got %s", after)
	}
}

func TestParseSnoozeDurationBareNumber(t *testing.T) {
	tests := []struct {
		name    string
		input   []string
		want    time.Duration
		wantErr bool
	}{
		{"bare 5 means 5m", []string{"snooze", "5"}, 5 * time.Minute, false},
		{"bare 10 means 10m", []string{"snooze", "10"}, 10 * time.Minute, false},
		{"explicit 5m still works", []string{"snooze", "5m"}, 5 * time.Minute, false},
		{"explicit 1h still works", []string{"snooze", "1h"}, time.Hour, false},
		{"invalid string errors", []string{"snooze", "abc"}, 0, true},
		{"missing arg errors", []string{"snooze"}, 0, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseSnoozeDuration(tt.input)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("got %v, want %v", got, tt.want)
			}
		})
	}
}
