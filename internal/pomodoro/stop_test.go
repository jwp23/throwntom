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
