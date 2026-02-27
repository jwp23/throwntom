package engine

import (
	"testing"
	"time"
)

func TestConfirmTransitionWorkToShortBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	if e.State() != AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm")
	}
	e.ConfirmNext()
	if e.State() != ShortBreak {
		t.Fatalf("expected ShortBreak")
	}
}

func TestConfirmTransitionBreakToWork(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	if e.State() != Work {
		t.Fatalf("expected Work")
	}
}

func TestEveryFourthWorkGoesToLongBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for i := 0; i < 3; i++ {
		e.MarkPeriodComplete()
		e.ConfirmNext()
		e.MarkPeriodComplete()
		e.ConfirmNext()
	}
	e.MarkPeriodComplete()
	e.ConfirmNext()
	if e.State() != LongBreak {
		t.Fatalf("expected LongBreak, got %v", e.State())
	}
}

func TestSnoozeDoesNotChangePhase(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	if e.State() != AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm")
	}
	e.Snooze(10 * time.Second)
	if e.State() != AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm after snooze")
	}
}

func TestCompletedTodayResetsOnFirstStart(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	if e.CompletedToday() != 1 {
		t.Fatalf("expected completedToday=1")
	}
	e.SkipToday()
	e.StartWork()
	if e.CompletedToday() != 0 {
		t.Fatalf("expected reset on first start, got %d", e.CompletedToday())
	}
}
