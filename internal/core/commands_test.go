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
	c.timer.CompletePeriod()
	if c.timer.State() != engine.AwaitingConfirm {
		t.Fatalf("precondition: expected AwaitingConfirm, got %s", c.timer.State())
	}

	c.execute("")

	if c.timer.State() == engine.AwaitingConfirm {
		t.Fatalf("expected empty input to advance out of AwaitingConfirm")
	}
	if c.timer.State() != engine.ShortBreak {
		t.Fatalf("expected ShortBreak after confirm, got %s", c.timer.State())
	}
}

func TestEmptyInputOutsideAwaitingConfirmIsNoop(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})

	before := c.timer.State()
	result := c.execute("")
	if result.err != nil {
		t.Fatalf("unexpected error on empty input: %v", result.err)
	}
	if c.timer.State() != before {
		t.Fatalf("empty input should not change state, got %s → %s", before, c.timer.State())
	}

	c.execute(cmdStart)
	workBefore := c.timer.State()
	c.execute("")
	if c.timer.State() != workBefore {
		t.Fatalf("empty input during work should not change state, got %s → %s", workBefore, c.timer.State())
	}
}

func TestTypedConfirmStillAdvances(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdStart)
	c.timer.CompletePeriod()

	c.execute("confirm")

	if c.timer.State() != engine.ShortBreak {
		t.Fatalf("expected ShortBreak after typed confirm, got %s", c.timer.State())
	}
}

func TestNewCycleCommandResetsCycleProgressButKeepsDailyTotal(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})

	c.execute(cmdStart)
	c.timer.CompletePeriod()
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

func TestExecuteClassifiesErrors(t *testing.T) {
	tests := []struct {
		name string
		line string
		want ErrorKind
	}{
		{"unknown command", "bogus", ErrorUsage},
		{"bad snooze duration", "snooze bogus", ErrorUsage},
		{"missing task argument", "task done", ErrorUsage},
		{"task out of range", "task done 99", ErrorUsage},
		{"unknown task subcommand", "task bogus", ErrorUsage},
		{"pause while idle", "pause", ErrorRefused},
		{"resume while idle", "resume", ErrorRefused},
		{"focus outside work session", "task focus 1", ErrorRefused},
		{"successful command", "status", ErrorNone},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := newTestCoreWithTasks(t)
			resp := c.Execute(tt.line)
			if resp.ErrorKind != tt.want {
				t.Fatalf("kind = %v (error %q), want %v", resp.ErrorKind, resp.Error, tt.want)
			}
		})
	}
}

func TestExecuteClassifiesAlreadyFocusedAsRefused(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute(cmdTaskAddImportant)
	c.execute("start") // enters focus prompt
	c.execute("")      // skip prompt, start pomodoro
	if resp := c.Execute(cmdTaskFocus1); resp.ErrorKind != ErrorNone {
		t.Fatalf("first focus: kind = %v error %q", resp.ErrorKind, resp.Error)
	}
	resp := c.Execute(cmdTaskFocus1)
	if resp.ErrorKind != ErrorRefused {
		t.Fatalf("kind = %v (error %q), want ErrorRefused", resp.ErrorKind, resp.Error)
	}
}
