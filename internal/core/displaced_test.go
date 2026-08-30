package core

import (
	"testing"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// Stop is a suspend and the break it leaves owed survives it (throwntom-k08).
// Start must not be the one verb that throws that same break away: at the
// awaiting-confirm boundary it means confirm.
func TestStartAtAwaitingConfirmEntersTheOwedBreak(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.timer.CompletePeriod()
	c.execute("start")

	if got := c.timer.State(); got != engine.ShortBreak {
		t.Fatalf("expected the owed short break, got %v", got)
	}
	if got := countEvents(t, path, "break_started"); got != 1 {
		t.Fatalf("expected the break to be logged as started, got %d", got)
	}
}

// The engine counts a phase the moment it finishes, and only a confirm logs
// that completion. A start that walked past awaiting-confirm left the engine
// claiming a pomodoro the event log had never seen.
func TestStartAtAwaitingConfirmCreditsTheFinishedPomodoro(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.timer.CompletePeriod()
	c.execute("start")

	if got := countEvents(t, path, "pomodoro_completed"); got != 1 {
		t.Fatalf("one finished work period must yield one completion, got %d", got)
	}
	if got := countEvents(t, path, "pomodoro_started"); got != 1 {
		t.Fatalf("only one pomodoro was ever started, got %d", got)
	}
	if got := c.timer.Snapshot().Engine.CompletedToday; got != 1 {
		t.Fatalf("engine counted %d completions; the log must agree", got)
	}
}

// New-cycle does abandon the cycle, but the phase that finished still
// happened: it is credited on the way past, or the dashboard loses it.
func TestNewCycleAtAwaitingConfirmCreditsTheFinishedPomodoro(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.timer.CompletePeriod()
	c.execute("new-cycle")

	if got := c.timer.State(); got != engine.Work {
		t.Fatalf("new-cycle starts fresh work, got %v", got)
	}
	if got := countEvents(t, path, "pomodoro_completed"); got != 1 {
		t.Fatalf("one finished work period must yield one completion, got %d", got)
	}
}

// A skipped phase was never earned, so nothing may credit it — the same guard
// confirm and stop apply.
func TestNewCycleAfterASkipCreditsNothing(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.execute("skip")
	c.execute("new-cycle")

	if got := countEvents(t, path, "pomodoro_completed"); got != 0 {
		t.Fatalf("a skipped phase must not be credited, got %d completions", got)
	}
}

func TestStartAfterASkipCreditsNothing(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.execute("skip")
	c.execute("start")

	if got := countEvents(t, path, "pomodoro_completed"); got != 0 {
		t.Fatalf("a skipped phase must not be credited, got %d completions", got)
	}
}
