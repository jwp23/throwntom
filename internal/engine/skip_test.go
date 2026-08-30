package engine

import "testing"

// Skip ends the running phase early. It reaches the same boundary a phase that
// ran its course reaches — the next stage, awaiting confirmation — but credits
// nothing, because a skipped period was not served.

func TestSkipWorkAwaitsConfirmation(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	if !e.SkipPhase() {
		t.Fatal("expected a running work phase to be skippable")
	}
	if got := e.State(); got != AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm, got %v", got)
	}
	if got := e.Snapshot().LastPhase; got != Work {
		t.Fatalf("expected last_phase work, got %v", got)
	}
}

func TestSkippedWorkIsNotCounted(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.SkipPhase()

	if got := e.CompletedToday(); got != 0 {
		t.Fatalf("a skipped pomodoro was not worked and must not inflate the day, got %d", got)
	}
	if got := e.WorkSessionsInBlock(); got != 0 {
		t.Fatalf("a skipped pomodoro must not advance the long-break cycle, got %d", got)
	}
}

// The long break is earned by pomodoros actually completed. With no completed
// session in the block the remainder is zero, which must not be read as a full
// cycle.
func TestSkippedFirstWorkOffersAShortBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.SkipPhase()

	if got := e.NextPhase(); got != ShortBreak {
		t.Fatalf("expected a short break after skipping the first pomodoro, got %v", got)
	}
}

// Sitting in work with a full block means the long break for that block has
// already been taken; skipping this pomodoro must not hand out a second one.
func TestSkippedWorkAfterALongBreakOffersAShortBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for i := 0; i < 4; i++ {
		e.MarkPeriodComplete()
		e.ConfirmNext()
		e.MarkPeriodComplete()
		e.ConfirmNext()
	}
	if got := e.State(); got != Work {
		t.Fatalf("expected to be back in work after the long break, got %v", got)
	}
	e.SkipPhase()

	if got := e.NextPhase(); got != ShortBreak {
		t.Fatalf("expected a short break after skipping a pomodoro, got %v", got)
	}
}

func TestCompletedWorkStillEarnsItsLongBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for i := 0; i < 3; i++ {
		e.MarkPeriodComplete()
		e.ConfirmNext()
		e.MarkPeriodComplete()
		e.ConfirmNext()
	}
	e.MarkPeriodComplete()

	if got := e.NextPhase(); got != LongBreak {
		t.Fatalf("expected the fourth completed pomodoro to earn a long break, got %v", got)
	}
}

func TestSkipBreakOffersWork(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.ConfirmNext() // short break, running
	if !e.SkipPhase() {
		t.Fatal("expected a running break to be skippable")
	}
	if got := e.NextPhase(); got != Work {
		t.Fatalf("expected work after skipping a break, got %v", got)
	}
	if got := e.CompletedToday(); got != 1 {
		t.Fatalf("skipping a break must not disturb the day's pomodoro total, got %d", got)
	}
}

func TestSkipRefusedWhenNoPhaseIsRunning(t *testing.T) {
	idle := New(25, 5, 15, 4)

	awaiting := New(25, 5, 15, 4)
	awaiting.StartWork()
	awaiting.MarkPeriodComplete()

	paused := New(25, 5, 15, 4)
	paused.StartWork()
	paused.Pause()

	for name, e := range map[string]*Engine{"idle": idle, "awaiting confirm": awaiting, "paused": paused} {
		before := e.Snapshot()
		if e.SkipPhase() {
			t.Fatalf("expected skip to be refused while %s", name)
		}
		if e.Snapshot() != before {
			t.Fatalf("a refused skip while %s must change nothing", name)
		}
	}
}
