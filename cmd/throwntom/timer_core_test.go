package main

import (
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v2/internal/config"
)

type noopNotifier struct{}

func (noopNotifier) PlaySound(string) error {
	return nil
}

func TestNewTimerCoreDefaultsMorningPendingTrue(t *testing.T) {
	core := newTimerCore(config.Default(), noopNotifier{})
	if !core.state.isMorningPending() {
		t.Fatal("expected morning reminder pending by default")
	}
}

func TestNewTimerCoreRespectsMorningReminderPendingFalse(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false

	core := newTimerCore(cfg, noopNotifier{})
	if core.state.isMorningPending() {
		t.Fatal("expected morning reminder pending to be false")
	}
}

func TestBeginMorningLoopStartsWhenPendingTrue(t *testing.T) {
	state := &reminderState{morningPending: true}
	ctx, started := state.beginMorningLoop()
	if !started {
		t.Fatal("expected beginMorningLoop to start when morningPending is true but no loop running")
	}
	if ctx == nil {
		t.Fatal("expected non-nil context")
	}
	// Clean up
	state.stopMorningLoop()
}

func TestBeginMorningLoopRejectsDuplicateLoop(t *testing.T) {
	state := &reminderState{}
	ctx, started := state.beginMorningLoop()
	if !started {
		t.Fatal("expected first beginMorningLoop to start")
	}
	if ctx == nil {
		t.Fatal("expected non-nil context from first call")
	}

	_, startedAgain := state.beginMorningLoop()
	if startedAgain {
		t.Fatal("expected second beginMorningLoop to be rejected (duplicate prevention)")
	}
	// Clean up
	state.stopMorningLoop()
}

func TestNewCycleCommandResetsCycleProgressButKeepsDailyTotal(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})

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
