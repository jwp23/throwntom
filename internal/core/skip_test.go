package core

import (
	"errors"
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

func TestSkipAdvancesToTheNextStage(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	result := c.execute("skip")

	if result.err != nil {
		t.Fatalf("unexpected error: %v", result.err)
	}
	if got := c.timer.State(); got != engine.AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm, got %v", got)
	}
	if !hasEventType(readEvents(t, path), "skipped") {
		t.Fatal("expected a skipped event")
	}
}

// A skipped pomodoro was not worked: counting it would inflate the daily total
// and make the streak lie.
func TestSkippedWorkIsNotCountedAsCompleted(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.execute("skip")
	c.execute("confirm")

	if hasEventType(readEvents(t, path), "pomodoro_completed") {
		t.Fatal("a skipped pomodoro must not be logged as completed")
	}
	line, _, _ := c.Status()
	if !strings.Contains(line, "Today: 0") {
		t.Fatalf("expected the day's total untouched by a skip, got %q", line)
	}
}

func TestSkipRefusedWhenNothingIsRunning(t *testing.T) {
	c, _ := newCoreWithEvents(t)
	result := c.execute("skip")

	if result.err == nil {
		t.Fatal("expected skip to be refused while idle")
	}
	if !errors.Is(result.err, errNotRunning) {
		t.Fatalf("expected a state refusal, got %v", result.err)
	}
	if classifyError(result.err) != ErrorRefused {
		t.Fatal("expected skip's refusal to classify as ErrorRefused")
	}
}
