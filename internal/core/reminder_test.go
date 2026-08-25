package core

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

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

func TestStartBeginsMorningLoopWhenPendingAndIdle(t *testing.T) {
	cfg := config.Default()
	c := newCore(cfg, noopNotifier{})
	// Monday at 10:00 — after default schedule 09:15
	c.now = func() time.Time { return time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local) }

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c.Start(ctx)
	defer c.Stop()

	c.state.mu.Lock()
	hasCancel := c.state.morningCancel != nil
	c.state.mu.Unlock()
	if !hasCancel {
		t.Fatal("expected morning loop to be running after start with morningPending=true and idle engine")
	}
}

func TestStartSkipsMorningLoopWhenNotPending(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c.Start(ctx)
	defer c.Stop()

	c.state.mu.Lock()
	hasCancel := c.state.morningCancel != nil
	c.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected no morning loop when morningPending=false")
	}
}

func TestStartSkipsMorningLoopWhenEngineNotIdle(t *testing.T) {
	cfg := config.Default()
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdStart) // engine transitions to Work, stopMorningLoop clears morningPending

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c.Start(ctx)
	defer c.Stop()

	c.state.mu.Lock()
	hasCancel := c.state.morningCancel != nil
	c.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected no morning loop when engine is not idle")
	}
}

func TestStartSkipsMorningLoopBeforeScheduledTime(t *testing.T) {
	cfg := config.Default()
	c := newCore(cfg, noopNotifier{})
	// Monday at 08:00 — before default schedule 09:15
	c.now = func() time.Time { return time.Date(2026, 3, 2, 8, 0, 0, 0, time.Local) }

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c.Start(ctx)
	defer c.Stop()

	c.state.mu.Lock()
	hasCancel := c.state.morningCancel != nil
	c.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected no morning loop before scheduled time")
	}
}

func TestStartBeginsMorningLoopAfterScheduledTime(t *testing.T) {
	cfg := config.Default()
	c := newCore(cfg, noopNotifier{})
	// Monday at 11:30 — after default schedule 09:15
	c.now = func() time.Time { return time.Date(2026, 3, 2, 11, 30, 0, 0, time.Local) }

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c.Start(ctx)
	defer c.Stop()

	c.state.mu.Lock()
	hasCancel := c.state.morningCancel != nil
	c.state.mu.Unlock()
	if !hasCancel {
		t.Fatal("expected morning loop to be running after scheduled time")
	}
}

func TestMorningSnoozeRestartsLoopAfterExpiry(t *testing.T) {
	cfg := config.Default()
	c := newCore(cfg, noopNotifier{})
	c.now = func() time.Time { return time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local) }

	// Start morning loop manually to simulate scheduler trigger
	startMorningLoop(c.state, c.repeatInterval, c.notifier)

	// Snooze for a tiny duration
	result := c.execute("snooze 1ms")
	if result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}
	if !strings.Contains(result.message, "morning reminder snoozed") {
		t.Fatalf("expected morning snooze message, got %q", result.message)
	}

	// Morning loop should be stopped immediately after snooze
	c.state.mu.Lock()
	hasCancel := c.state.morningCancel != nil
	c.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected morning loop to be stopped during snooze")
	}

	// Wait for snooze to expire and goroutine to re-trigger
	time.Sleep(50 * time.Millisecond)

	c.state.mu.Lock()
	hasCancel = c.state.morningCancel != nil
	c.state.mu.Unlock()
	if !hasCancel {
		t.Fatal("expected morning loop to be restarted after snooze expiry")
	}
	c.state.stopMorningLoop()
}

func TestMorningSnoozeSkipsRestartIfNotIdle(t *testing.T) {
	cfg := config.Default()
	c := newCore(cfg, noopNotifier{})
	c.now = func() time.Time { return time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local) }

	// Start morning loop manually
	startMorningLoop(c.state, c.repeatInterval, c.notifier)

	// Snooze for a tiny duration
	result := c.execute("snooze 1ms")
	if result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}

	// Start a pomodoro before snooze expires
	c.execute(cmdStart)
	if c.cycle.State() != engine.Work {
		t.Fatal("expected engine to be in Work state")
	}

	// Wait for snooze goroutine to fire
	time.Sleep(50 * time.Millisecond)

	// Morning loop should NOT restart since engine is not idle
	c.state.mu.Lock()
	hasCancel := c.state.morningCancel != nil
	c.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected morning loop to NOT restart when engine is not idle")
	}
	c.cycle.Stop()
}

func TestMorningSnoozeStopMidSnooze(t *testing.T) {
	cfg := config.Default()
	c := newCore(cfg, noopNotifier{})
	c.now = func() time.Time { return time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local) }

	// Start morning loop manually
	startMorningLoop(c.state, c.repeatInterval, c.notifier)

	// Snooze for a longer duration
	result := c.execute("snooze 100ms")
	if result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}

	// Start a pomodoro (which calls stopMorningLoop + clearSnooze)
	c.execute(cmdStart)

	// Wait for the snooze goroutine to fire
	time.Sleep(150 * time.Millisecond)

	// The goroutine should not interfere — engine is not idle
	c.state.mu.Lock()
	hasCancel := c.state.morningCancel != nil
	c.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected no morning loop interference after start during snooze")
	}
	c.cycle.Stop()
}
