package main

import (
	"strings"
	"testing"

	"github.com/jwp23/throwntom/internal/config"
)

type noopNotifier struct{}

func (noopNotifier) PlaySound(string) error {
	return nil
}

func TestNewDaemonCoreDefaultsMorningPendingTrue(t *testing.T) {
	core := newDaemonCore(config.Default(), noopNotifier{})
	if !core.state.isMorningPending() {
		t.Fatal("expected morning reminder pending by default")
	}
}

func TestNewDaemonCoreRespectsMorningReminderPendingFalse(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false

	core := newDaemonCore(cfg, noopNotifier{})
	if core.state.isMorningPending() {
		t.Fatal("expected morning reminder pending to be false")
	}
}

func TestNewCycleCommandResetsCycleProgressButKeepsDailyTotal(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newDaemonCore(cfg, noopNotifier{})

	core.execute("start")
	core.cycle.CompletePeriod()
	before, _ := core.snapshot()
	if !strings.Contains(before, "today's pomodoros=1") {
		t.Fatalf("expected baseline daily total, got %s", before)
	}

	result := core.execute("new-cycle")
	if result.err != nil {
		t.Fatalf("new-cycle command failed: %v", result.err)
	}

	after, _ := core.snapshot()
	if !strings.Contains(after, "pomodoro") {
		t.Fatalf("expected pomodoro state, got %s", after)
	}
	if !strings.Contains(after, "pomodoros=0/4") {
		t.Fatalf("expected cycle reset, got %s", after)
	}
	if !strings.Contains(after, "today's pomodoros=1") {
		t.Fatalf("expected daily total preserved, got %s", after)
	}
}
