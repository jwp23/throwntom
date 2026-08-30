package core

import (
	"errors"
	"testing"
)

func countEvents(t *testing.T, path, typ string) int {
	t.Helper()
	n := 0
	for _, ev := range readEvents(t, path) {
		if ev.Type == typ {
			n++
		}
	}
	return n
}

// lastPhase outlives the state that earned it — stop keeps it owed — so an
// unguarded confirm would log that one work period's completion again on every
// call, permanently inflating the dashboard from an append-only log.
func TestStrayConfirmAfterStopDoesNotDoubleCount(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.timer.CompletePeriod()
	c.execute("stop")
	c.execute("confirm")
	c.execute("confirm")

	if got := countEvents(t, path, "pomodoro_completed"); got != 1 {
		t.Fatalf("one work period must yield exactly one completion, got %d", got)
	}
}

func TestConfirmMidPhaseIsRefusedAndLogsNothing(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	result := c.execute("confirm")

	if !errors.Is(result.err, errNothingToConfirm) {
		t.Fatalf("expected confirm to be refused mid-phase, got %v", result.err)
	}
	if got := countEvents(t, path, "pomodoro_completed"); got != 0 {
		t.Fatalf("a refused confirm must log nothing, got %d completions", got)
	}
	if classifyError(result.err) != ErrorRefused {
		t.Fatal("expected confirm's refusal to classify as ErrorRefused")
	}
}
