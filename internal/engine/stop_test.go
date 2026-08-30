package engine

import (
	"testing"
	"time"
)

// Stop is a suspend, not an abandon: it puts the cycle down without throwing
// away what was earned, so a later start picks the cycle back up where it was.

func TestStopKeepsOwedBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.Stop()

	if got := e.State(); got != Idle {
		t.Fatalf("expected Idle after stop, got %v", got)
	}
	if got := e.Snapshot().LastPhase; got != Work {
		t.Fatalf("expected the owed break to be remembered as last_phase work, got %v", got)
	}
}

func TestStopKeepsCycleProgress(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.Stop()

	if got := e.WorkSessionsInBlock(); got != 1 {
		t.Fatalf("expected cycle progress preserved, got %d", got)
	}
	if got := e.CompletedToday(); got != 1 {
		t.Fatalf("expected the day's total preserved, got %d", got)
	}
}

func TestStartAfterStopEntersOwedShortBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.Stop()
	e.StartWork()

	if got := e.State(); got != ShortBreak {
		t.Fatalf("expected the break earned before the stop, got %v", got)
	}
}

func TestStartAfterStopEntersOwedLongBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for i := 0; i < 3; i++ {
		e.MarkPeriodComplete()
		e.ConfirmNext()
		e.MarkPeriodComplete()
		e.ConfirmNext()
	}
	e.MarkPeriodComplete()
	e.Stop()
	e.StartWork()

	if got := e.State(); got != LongBreak {
		t.Fatalf("expected the long break earned before the stop, got %v", got)
	}
}

func TestStartAfterStoppingAnOwedWorkPeriodEntersWork(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.ConfirmNext() // short break
	e.MarkPeriodComplete()
	e.Stop()
	e.StartWork()

	if got := e.State(); got != Work {
		t.Fatalf("expected work owed after a completed break, got %v", got)
	}
}

// A phase cut short mid-flight was not finished, so it earns nothing: coming
// back starts a fresh work period rather than the break a completed one owes.

func TestStoppingMidWorkOwesNothing(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.Stop()
	e.StartWork()

	if got := e.State(); got != Work {
		t.Fatalf("expected work after stopping mid-work, got %v", got)
	}
}

func TestStoppingMidBreakOwesNothing(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.ConfirmNext() // short break, running
	e.Stop()
	e.StartWork()

	if got := e.State(); got != Work {
		t.Fatalf("expected work after stopping mid-break, got %v", got)
	}
}

func TestStoppingWhilePausedOwesNothing(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.Pause()
	e.Stop()

	if got := e.Snapshot().PausedFrom; got != Idle {
		t.Fatalf("expected paused_from cleared by stop, got %v", got)
	}
	e.StartWork()
	if got := e.State(); got != Work {
		t.Fatalf("expected work after stopping a paused phase, got %v", got)
	}
}

// A suspended cycle is a fact about today. A new day owes nothing, and neither
// does a day the user skipped.

func TestNewDayClearsTheOwedPhase(t *testing.T) {
	e := New(25, 5, 15, 4)
	day1 := time.Date(2026, 8, 29, 9, 0, 0, 0, time.Local)
	e.AdvanceDay(day1)
	e.StartWork()
	e.MarkPeriodComplete()
	e.Stop()

	e.AdvanceDay(day1.AddDate(0, 0, 1))
	if got := e.Snapshot().LastPhase; got != Idle {
		t.Fatalf("expected a new day to owe nothing, got last_phase %v", got)
	}
	e.StartWork()
	if got := e.State(); got != Work {
		t.Fatalf("expected work on a new day, got %v", got)
	}
}

func TestStartAfterSkipTodayEntersWork(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.SkipToday()
	e.StartWork()

	if got := e.State(); got != Work {
		t.Fatalf("expected work after skipping the day, got %v", got)
	}
}

func TestSnapshotInvalidAcceptsSuspendedCycle(t *testing.T) {
	suspended := []Snapshot{
		{State: Idle, LastPhase: Work, WorkSessions: 1, CompletedToday: 1, WorkDayStarted: true},
		{State: Idle, LastPhase: ShortBreak, WorkSessions: 1, CompletedToday: 1, WorkDayStarted: true},
		{State: Idle, LastPhase: LongBreak, WorkSessions: 4, CompletedToday: 4, WorkDayStarted: true},
	}
	for _, s := range suspended {
		if reason := s.Invalid(); reason != "" {
			t.Fatalf("expected a stopped cycle with last_phase %v to be valid, got %q", s.LastPhase, reason)
		}
	}
}
