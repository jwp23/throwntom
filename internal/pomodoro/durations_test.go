package pomodoro

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

func TestApplyDurationsExtendsRunningPhase(t *testing.T) {
	a := New(25, 5, 15, 4)
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)

	a.ApplyDurations(30, 5, 15, 4)

	if got := a.State(); got != engine.Work {
		t.Fatalf("expected work to continue, got %s", got)
	}
	remaining := a.Snapshot().PhaseEndAt.Sub(clock.Now())
	if remaining != 20*time.Minute {
		t.Fatalf("expected 20m remaining of the new 30m phase, got %s", remaining)
	}
}

func TestApplyDurationsShortensRunningPhase(t *testing.T) {
	a := New(25, 5, 15, 4)
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)

	a.ApplyDurations(12, 5, 15, 4)

	remaining := a.Snapshot().PhaseEndAt.Sub(clock.Now())
	if remaining != 2*time.Minute {
		t.Fatalf("expected 2m remaining of the new 12m phase, got %s", remaining)
	}
	clock.Advance(2 * time.Minute)
	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("expected the re-derived phase to end on time, got %s", got)
	}
}

// A duration shorter than the elapsed time ends the phase on reload: ADR-006
// reads that edit as "this phase should already be over".
func TestApplyDurationsShorterThanElapsedEndsPhase(t *testing.T) {
	a := New(25, 5, 15, 4)
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)

	a.ApplyDurations(5, 5, 15, 4)

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("expected the phase to end, got %s", got)
	}
	if !a.Snapshot().PhaseEndAt.IsZero() {
		t.Fatalf("expected no phase end time after the phase ended")
	}
}

func TestApplyDurationsRederivesBreak(t *testing.T) {
	a := New(25, 5, 15, 4)
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	a.CompletePeriod()
	a.Confirm()
	clock.Advance(time.Minute)

	a.ApplyDurations(25, 9, 15, 4)

	if got := a.State(); got != engine.ShortBreak {
		t.Fatalf("expected short break, got %s", got)
	}
	remaining := a.Snapshot().PhaseEndAt.Sub(clock.Now())
	if remaining != 8*time.Minute {
		t.Fatalf("expected 8m remaining of the new 9m break, got %s", remaining)
	}
}

func TestApplyDurationsRederivesPausedRemaining(t *testing.T) {
	a := New(25, 5, 15, 4)
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)
	a.Pause()

	a.ApplyDurations(30, 5, 15, 4)

	if got := a.Snapshot().PausedRemaining; got != 20*time.Minute {
		t.Fatalf("expected 20m paused remaining, got %s", got)
	}
	a.Resume()
	if got := a.Snapshot().PhaseEndAt.Sub(clock.Now()); got != 20*time.Minute {
		t.Fatalf("expected resume to run the re-derived remainder, got %s", got)
	}
}

func TestApplyDurationsEndsPausedPhaseShorterThanElapsed(t *testing.T) {
	a := New(25, 5, 15, 4)
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)
	a.Pause()

	a.ApplyDurations(5, 5, 15, 4)

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("expected the paused phase to end, got %s", got)
	}
	if got := a.Snapshot().PausedRemaining; got != 0 {
		t.Fatalf("expected no paused remainder once the phase ended, got %s", got)
	}
	if got := a.Snapshot().Engine.CompletedToday; got != 1 {
		t.Fatalf("expected the ended pomodoro to be counted, got %d", got)
	}
}

func TestApplyDurationsLeavesIdleAlone(t *testing.T) {
	a := New(25, 5, 15, 4)
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)

	a.ApplyDurations(30, 5, 15, 4)

	if got := a.State(); got != engine.Idle {
		t.Fatalf("expected idle to stay idle, got %s", got)
	}
	a.Start()
	if got := a.Snapshot().PhaseEndAt.Sub(clock.Now()); got != 30*time.Minute {
		t.Fatalf("expected the next phase to use the new duration, got %s", got)
	}
}

func TestApplyDurationsChangesLongBreakEvery(t *testing.T) {
	a := New(25, 5, 15, 4)
	a.Start()
	a.CompletePeriod()

	a.ApplyDurations(25, 5, 15, 1)

	next, dur := a.NextStage()
	if next != engine.LongBreak {
		t.Fatalf("expected a long break under long_break_every=1, got %s", next)
	}
	if dur != 15*time.Minute {
		t.Fatalf("expected the long break duration, got %s", dur)
	}
}

func TestApplyDurationsNotifiesChange(t *testing.T) {
	a := New(25, 5, 15, 4)
	changed := 0
	a.SetOnChange(func() { changed++ })
	a.Start()
	before := changed

	a.ApplyDurations(30, 5, 15, 4)

	if changed == before {
		t.Fatalf("expected a change notification after reload")
	}
}
