package core

import (
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

func TestStopLogsAStoppedEvent(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.execute("stop")

	events := readEvents(t, path)
	if !hasEventType(events, "stopped") {
		t.Fatal("expected a stopped event to terminate the started pomodoro")
	}
}

func TestStopKeepsFocusedTasks(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add work item")
	c.execute("start") // enters focus prompt
	c.execute("")      // skip prompt, start pomodoro
	c.execute(cmdTaskFocus1)
	c.execute("stop")

	if len(c.Focused()) != 1 {
		t.Fatalf("stop suspends the cycle, so focus should survive it; got %d focused", len(c.Focused()))
	}
}

func TestStartAfterStopResumesTheOwedBreak(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.timer.CompletePeriod() // work done, awaiting confirm
	c.execute("stop")
	result := c.execute("start")

	if got := c.timer.State(); got != engine.ShortBreak {
		t.Fatalf("expected the owed short break, got %v", got)
	}
	if !strings.Contains(result.message, "short break") {
		t.Fatalf("expected the message to name the resumed phase, got %q", result.message)
	}
	events := readEvents(t, path)
	if !hasEventType(events, "break_started") {
		t.Fatal("expected resuming into a break to log break_started, not pomodoro_started")
	}
}

// The focus prompt asks which tasks this pomodoro is for, so it has no business
// appearing when the start is resuming an owed break.
func TestStartResumingABreakSkipsTheFocusPrompt(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add work item")
	c.execute("start")
	c.execute("")
	c.timer.CompletePeriod()
	c.execute("stop")
	c.execute("start")

	if c.FocusPromptPending() {
		t.Fatal("expected no focus prompt when a break is what resumes")
	}
	if got := c.timer.State(); got != engine.ShortBreak {
		t.Fatalf("expected the owed short break, got %v", got)
	}
}

func TestStartAfterStopStillPromptsForFocusWhenWorkIsOwed(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add work item")
	c.execute("start")
	c.execute("")
	c.execute("stop") // mid-work: nothing owed
	c.execute("start")

	if !c.FocusPromptPending() {
		t.Fatal("expected the focus prompt when work is what starts")
	}
}

// The engine counts the pomodoro that stop leaves owed, so the ledger must
// count it too — nothing else will, because a resuming start goes straight
// into the break rather than through confirm.
func TestStopRecordsTheCompletionItPreserves(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.timer.CompletePeriod()
	c.execute("stop")

	if !hasEventType(readEvents(t, path), "pomodoro_completed") {
		t.Fatal("stopping at awaiting-confirm lost the finished pomodoro from the log")
	}
}

// A skipped phase was not served, so stopping on top of it records nothing.
func TestStopAfterASkipRecordsNoCompletion(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.execute("skip")
	c.execute("stop")

	if hasEventType(readEvents(t, path), "pomodoro_completed") {
		t.Fatal("a skipped pomodoro must not be recorded as completed by stop")
	}
}

func TestStopWhileIdleLogsNothing(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("stop")

	if hasEventType(readEvents(t, path), "stopped") {
		t.Fatal("stopping an idle timer is a no-op and must not log an event")
	}
}

// Preserving focus across a stop is worthless if the prompt that the next
// start opens throws it away: the prompt must come up with the surviving
// focus already ticked.
func TestFocusSurvivesTheStartPromptAfterAStop(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add work item")
	c.execute("start")
	c.execute("")
	c.execute(cmdTaskFocus1)
	c.execute("stop")

	c.execute("start") // mid-phase stop owed nothing, so work starts and prompts
	c.execute("")      // accept the prompt as it stands

	if len(c.Focused()) != 1 {
		t.Fatalf("the start prompt dropped the focus stop preserved; got %d", len(c.Focused()))
	}
}
