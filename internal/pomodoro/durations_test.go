package pomodoro

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

func TestApplyDurationsExtendsRunningPhase(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)

	a.ApplyDurations(minutes(30, 5, 15, 4))

	if got := a.State(); got != engine.Work {
		t.Fatalf("expected work to continue, got %s", got)
	}
	remaining := a.Snapshot().PhaseEndAt.Sub(clock.Now())
	if remaining != 20*time.Minute {
		t.Fatalf("expected 20m remaining of the new 30m phase, got %s", remaining)
	}
}

func TestApplyDurationsShortensRunningPhase(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)

	a.ApplyDurations(minutes(12, 5, 15, 4))

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
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)

	a.ApplyDurations(minutes(5, 5, 15, 4))

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("expected the phase to end, got %s", got)
	}
	if !a.Snapshot().PhaseEndAt.IsZero() {
		t.Fatalf("expected no phase end time after the phase ended")
	}
}

// TestApplyDurationsTransitionsOnlyWhenStateActuallyChanges pins the guard
// ApplyDurations' deferred func applies: transitionLocked must fire when the
// reload ends the phase, and must not fire when the reload leaves the phase
// running, per the comment on ApplyDurations — an unwarranted transition
// would answer whatever reminder is outstanding.
func TestApplyDurationsTransitionsOnlyWhenStateActuallyChanges(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	transitions := 0
	a.SetOnTransition(func(engine.State) { transitions++ })
	a.Start()
	clock.Advance(10 * time.Minute)
	transitions = 0 // Start() itself is a transition (Idle -> Work); only what follows matters here

	a.ApplyDurations(minutes(30, 5, 15, 4)) // still running: no transition
	if transitions != 0 {
		t.Fatalf("expected no transition when the phase keeps running, got %d", transitions)
	}

	a.ApplyDurations(minutes(5, 5, 15, 4)) // shorter than elapsed: ends the phase
	if transitions != 1 {
		t.Fatalf("expected exactly one transition when the reload ends the phase, got %d", transitions)
	}
}

// TestApplyDurationsExactlyAtElapsedEndsPhase pins the "<= 0" boundary in
// rederiveRunningLocked: a new duration exactly equal to the elapsed time
// must end the phase, not start a zero-length one.
func TestApplyDurationsExactlyAtElapsedEndsPhase(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)

	a.ApplyDurations(minutes(10, 5, 15, 4)) // new duration == elapsed exactly

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("expected the phase to end when the new duration exactly matches elapsed time, got %s", got)
	}
}

// TestApplyDurationsPausedExactlyAtElapsedEndsPhase pins the "> 0" boundary
// in rederivePausedLocked: a paused phase whose new duration exactly equals
// the elapsed time must end, not resume with a zero remainder.
func TestApplyDurationsPausedExactlyAtElapsedEndsPhase(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)
	a.Pause()

	a.ApplyDurations(minutes(10, 5, 15, 4)) // new duration == elapsed exactly

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("expected the paused phase to end when the new duration exactly matches elapsed time, got %s", got)
	}
	if got := a.Snapshot().PausedRemaining; got != 0 {
		t.Fatalf("expected no paused remainder once the phase ended, got %s", got)
	}
}

func TestApplyDurationsRederivesBreak(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	a.CompletePeriod()
	a.Confirm()
	clock.Advance(time.Minute)

	a.ApplyDurations(minutes(25, 9, 15, 4))

	if got := a.State(); got != engine.ShortBreak {
		t.Fatalf("expected short break, got %s", got)
	}
	remaining := a.Snapshot().PhaseEndAt.Sub(clock.Now())
	if remaining != 8*time.Minute {
		t.Fatalf("expected 8m remaining of the new 9m break, got %s", remaining)
	}
}

func TestApplyDurationsRederivesPausedRemaining(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)
	a.Pause()

	a.ApplyDurations(minutes(30, 5, 15, 4))

	if got := a.Snapshot().PausedRemaining; got != 20*time.Minute {
		t.Fatalf("expected 20m paused remaining, got %s", got)
	}
	a.Resume()
	if got := a.Snapshot().PhaseEndAt.Sub(clock.Now()); got != 20*time.Minute {
		t.Fatalf("expected resume to run the re-derived remainder, got %s", got)
	}
}

func TestApplyDurationsEndsPausedPhaseShorterThanElapsed(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(10 * time.Minute)
	a.Pause()

	a.ApplyDurations(minutes(5, 5, 15, 4))

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
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)

	a.ApplyDurations(minutes(30, 5, 15, 4))

	if got := a.State(); got != engine.Idle {
		t.Fatalf("expected idle to stay idle, got %s", got)
	}
	a.Start()
	if got := a.Snapshot().PhaseEndAt.Sub(clock.Now()); got != 30*time.Minute {
		t.Fatalf("expected the next phase to use the new duration, got %s", got)
	}
}

func TestApplyDurationsChangesLongBreakEvery(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	a.Start()
	a.CompletePeriod()

	a.ApplyDurations(minutes(25, 5, 15, 1))

	next, dur := a.NextStage()
	if next != engine.LongBreak {
		t.Fatalf("expected a long break under long_break_every=1, got %s", next)
	}
	if dur != 15*time.Minute {
		t.Fatalf("expected the long break duration, got %s", dur)
	}
}

func TestApplyDurationsNotifiesChange(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	changed := 0
	a.SetOnChange(func() { changed++ })
	a.Start()
	before := changed

	a.ApplyDurations(minutes(30, 5, 15, 4))

	if changed == before {
		t.Fatalf("expected a change notification after reload")
	}
}
