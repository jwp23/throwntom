package engine

import "testing"

func TestSetLongBreakEveryChangesTheCycleLength(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()

	e.SetLongBreakEvery(1)

	if got := e.LongBreakEvery(); got != 1 {
		t.Fatalf("expected long break every 1, got %d", got)
	}
	if got := e.NextPhase(); got != LongBreak {
		t.Fatalf("expected the shorter cycle to apply at once, got %s", got)
	}
}
