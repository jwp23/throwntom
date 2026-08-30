package pomodoro

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// Stop suspends the cycle, so a later Start resumes the owed phase — and must
// run it for that phase's own duration, not the work duration.
func TestStartAfterStopRunsTheOwedBreakForItsOwnDuration(t *testing.T) {
	a := New(25, 5, 15, 4)
	clk := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.Local))
	a.now = clk.Now
	a.after = clk.After

	a.Start()
	a.CompletePeriod()
	a.Stop()
	a.Start()

	if got := a.State(); got != engine.ShortBreak {
		t.Fatalf("expected the owed short break, got %v", got)
	}
	snap := a.Snapshot()
	if got := snap.PhaseEndAt.Sub(clk.Now()); got != 5*time.Minute {
		t.Fatalf("expected a 5m short break, got %v", got)
	}
}

func TestOwedPhaseReportsWhatStartWouldEnter(t *testing.T) {
	a := New(25, 5, 15, 4)
	if got := a.OwedPhase(); got != engine.Work {
		t.Fatalf("expected work owed on a fresh timer, got %v", got)
	}
	a.Start()
	a.CompletePeriod()
	a.Stop()
	if got := a.OwedPhase(); got != engine.ShortBreak {
		t.Fatalf("expected a short break owed after stopping at awaiting-confirm, got %v", got)
	}
}

// Stop must report the state as of when it actually stopped, not a state a
// caller fetched earlier through a separate Snapshot call. The real deadline
// callback runs in its own goroutine (time.AfterFunc) and can complete the
// phase between a caller's Snapshot and its later Stop; a caller relying on
// the earlier, now-stale Snapshot would think the phase was still Work and
// skip logging its completion. Reporting the phase from inside Stop's own
// lock, the way Skip already does, means the caller never has to trust a
// separately-fetched value — Stop's own return is authoritative regardless
// of what ran in between.
func TestStopReportsTheStateAsOfWhenItActuallyStopped(t *testing.T) {
	a := New(25, 5, 15, 4)
	a.Start() // Work

	// What an old-style caller (Snapshot, then act, then Stop) would have
	// fetched before anything else happened.
	stale := a.Snapshot().Engine
	if stale.State != engine.Work {
		t.Fatalf("test setup: expected the earlier snapshot to read Work, got %v", stale.State)
	}

	// The deadline completes the phase — in production this is the
	// concurrent time.AfterFunc callback; CompletePeriod stands in for it
	// deterministically.
	a.CompletePeriod()

	got := a.Stop()

	if got.State != engine.AwaitingConfirm {
		t.Fatalf("Stop must report the live state (AwaitingConfirm) rather than an earlier, now-stale snapshot (%v)", stale.State)
	}
	if got.Skipped {
		t.Fatal("a completed phase must not be reported as skipped")
	}
}
