package pomodoro

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

func TestSkipEndsTheRunningPhaseNow(t *testing.T) {
	a := New(25, 5, 15, 4)
	clk := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.Local))
	a.now = clk.Now
	a.after = clk.After

	a.Start()
	if !a.Skip() {
		t.Fatal("expected a running phase to be skippable")
	}
	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm, got %v", got)
	}
	snap := a.Snapshot()
	if !snap.PhaseEndAt.IsZero() || !snap.PhaseStartedAt.IsZero() {
		t.Fatalf("expected the phase clock cleared, got %+v", snap)
	}
}

// The countdown must be cancelled, or the skipped phase completes a second
// time when its original deadline arrives.
func TestSkipCancelsTheCountdown(t *testing.T) {
	a := New(25, 5, 15, 4)
	clk := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.Local))
	a.now = clk.Now
	a.after = clk.After

	a.Start()
	a.Skip()
	clk.Advance(30 * time.Minute) // well past the skipped phase's own deadline

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("the skipped phase fired its deadline anyway, landing in %v", got)
	}
	if got := a.Snapshot().Engine.CompletedToday; got != 0 {
		t.Fatalf("the skipped phase completed itself later, crediting %d", got)
	}
}

func TestSkipRefusedWhenIdle(t *testing.T) {
	a := New(25, 5, 15, 4)
	if a.Skip() {
		t.Fatal("expected skip to be refused while idle")
	}
	if got := a.State(); got != engine.Idle {
		t.Fatalf("expected still Idle, got %v", got)
	}
}
