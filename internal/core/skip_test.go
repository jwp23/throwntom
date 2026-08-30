package core

import (
	"errors"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/config"
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
	if !errors.Is(result.err, errNothingToSkip) {
		t.Fatalf("expected a state refusal, got %v", result.err)
	}
	if !strings.Contains(result.err.Error(), "skip") {
		t.Fatalf("a refused skip must not talk about pausing, got %q", result.err)
	}
	if classifyError(result.err) != ErrorRefused {
		t.Fatal("expected skip's refusal to classify as ErrorRefused")
	}
}

// core discards a session whose snapshot Invalid() rejects, so a skip must not
// be able to write one: the round trip is what the user actually loses.
func TestSessionSurvivesASkippedFirstPomodoro(t *testing.T) {
	sessPath := filepath.Join(t.TempDir(), "session.json")
	cfg := config.Default()
	cfg.MorningReminderPending = false

	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	defer c.Stop()
	c.execute("start")
	c.execute("skip")
	c.execute("confirm") // into the short break
	c.saveSession()

	restored := newCore(cfg, noopNotifier{})
	restored.sessionPath = sessPath
	defer restored.Stop()
	if err := restored.loadSession(); err != nil {
		t.Fatalf("loadSession: %v", err)
	}
	if got := restored.timer.State(); got != engine.ShortBreak {
		t.Fatalf("the session was discarded on restart; state is %v", got)
	}
}
