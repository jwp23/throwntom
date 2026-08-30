package core

import (
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

func TestTaskFocusDuringWorkSession(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute(cmdTaskAddImportant)
	c.execute("start") // enters focus prompt
	c.execute("")      // skip prompt, start pomodoro
	result := c.execute(cmdTaskFocus1)
	if result.err != nil {
		t.Fatalf("focus failed: %v", result.err)
	}
	focused := c.Focused()
	if len(focused) != 1 {
		t.Fatalf("expected 1 focused, got %d", len(focused))
	}
	if focused[0].Description != "important work" {
		t.Fatalf("expected 'important work', got %q", focused[0].Description)
	}
}

func TestTaskFocusRejectsOutsideWorkSession(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute(cmdTaskAddImportant)
	result := c.execute(cmdTaskFocus1)
	if result.err == nil {
		t.Fatal("expected error when not in work session")
	}
}

func TestTaskUnfocus(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute(cmdTaskAddImportant)
	c.execute("start") // enters focus prompt
	c.execute("")      // skip prompt, start pomodoro
	c.execute(cmdTaskFocus1)
	result := c.execute("task unfocus 1")
	if result.err != nil {
		t.Fatal(result.err)
	}
	if len(c.Focused()) != 0 {
		t.Fatal("expected empty focused list after unfocus")
	}
}

func TestTaskUpDown(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add first")
	c.execute("task add second")
	c.execute("start") // enters focus prompt
	c.execute("")      // skip prompt, start pomodoro
	c.execute(cmdTaskFocus1)
	c.execute("task focus 2")
	c.execute("task up 2")
	focused := c.Focused()
	if len(focused) != 2 {
		t.Fatalf("expected 2 focused, got %d", len(focused))
	}
	if focused[0].Description != "second" {
		t.Fatalf("expected 'second' at top, got %q", focused[0].Description)
	}
	if focused[1].Description != "first" {
		t.Fatalf("expected 'first' at bottom, got %q", focused[1].Description)
	}
}

func TestStartEntersFocusPromptWhenTasksExist(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add something to do")
	result := c.execute("start")
	if !c.FocusPromptPending() {
		t.Fatal("expected focus prompt to be pending")
	}
	if !strings.Contains(result.message, "Select tasks") {
		t.Fatalf("expected prompt message, got %q", result.message)
	}
	if c.timer.State() != engine.Idle {
		t.Fatalf("expected idle during prompt, got %s", c.timer.State())
	}
}

func TestStartShowsPromptWhenNoTasks(t *testing.T) {
	c := newTestCoreWithTasks(t)
	result := c.execute("start")
	if !c.FocusPromptPending() {
		t.Fatal("expected focus prompt even when no tasks exist")
	}
	if !strings.Contains(result.message, "Select tasks") {
		t.Fatalf("expected prompt message, got %q", result.message)
	}
	if c.timer.State() != engine.Idle {
		t.Fatalf("expected idle during prompt, got %s", c.timer.State())
	}
}

func TestStartPromptEmptyListAllowsAddAndStart(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("start") // enters prompt even with no tasks
	c.execute("a new task from prompt")
	result := c.execute("") // confirm
	if c.FocusPromptPending() {
		t.Fatal("expected prompt cleared")
	}
	if c.timer.State() != engine.Work {
		t.Fatalf("expected pomodoro, got %s", c.timer.State())
	}
	focused := c.Focused()
	if len(focused) != 1 {
		t.Fatalf("expected 1 focused, got %d", len(focused))
	}
	if focused[0].Description != "new task from prompt" {
		t.Fatalf("expected 'new task from prompt', got %q", focused[0].Description)
	}
	_ = result
}

func TestStartPromptEmptyListSkipStarts(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("start") // enters prompt even with no tasks
	c.execute("")      // skip with no tasks
	if c.FocusPromptPending() {
		t.Fatal("expected prompt cleared")
	}
	if c.timer.State() != engine.Work {
		t.Fatalf("expected pomodoro, got %s", c.timer.State())
	}
	if len(c.Focused()) != 0 {
		t.Fatal("expected no focused tasks after skip")
	}
}

func TestFocusPromptToggleAndStart(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add first task")
	c.execute("task add second task")
	c.execute("start")       // enters prompt
	result := c.execute("1") // toggle task 1
	if !strings.Contains(result.message, "Focused") {
		t.Fatalf("expected focused info, got %q", result.message)
	}
	result = c.execute("") // empty enter = confirm and start
	if c.FocusPromptPending() {
		t.Fatal("expected prompt cleared")
	}
	if c.timer.State() != engine.Work {
		t.Fatalf("expected pomodoro, got %s", c.timer.State())
	}
	focused := c.Focused()
	if len(focused) != 1 {
		t.Fatalf("expected 1 focused, got %d", len(focused))
	}
	if focused[0].Description != "first task" {
		t.Fatalf("expected 'first task', got %q", focused[0].Description)
	}
}

func TestFocusPromptSkip(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add something")
	c.execute("start") // enters prompt
	c.execute("")      // skip (empty with no toggles)
	if c.FocusPromptPending() {
		t.Fatal("expected prompt cleared")
	}
	if c.timer.State() != engine.Work {
		t.Fatalf("expected pomodoro, got %s", c.timer.State())
	}
	if len(c.Focused()) != 0 {
		t.Fatal("expected no focused tasks after skip")
	}
}

func TestFocusPromptAddNewTask(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add existing")
	c.execute("start") // enters prompt
	result := c.execute("a brand new task")
	if !strings.Contains(result.message, "brand new task") {
		t.Fatalf("expected task in prompt, got %q", result.message)
	}
	active := c.tasks.Active()
	if len(active) != 2 {
		t.Fatalf("expected 2 active tasks, got %d", len(active))
	}
}

func TestConfirmToWorkTriggersFocusPrompt(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add keep working")
	c.execute("start")       // prompt
	c.execute("")            // skip prompt, start pomodoro
	c.timer.CompletePeriod() // work done -> awaiting confirm
	c.execute("confirm")     // -> short break (no prompt for breaks)
	if c.FocusPromptPending() {
		t.Fatal("should not prompt for break")
	}
	c.timer.CompletePeriod() // break done -> awaiting confirm
	c.execute("confirm")     // -> work (should trigger prompt)
	if !c.FocusPromptPending() {
		t.Fatal("expected focus prompt when confirming into work phase")
	}
}

func TestFocusPromptToggleOff(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add toggleable")
	c.execute("start") // enters prompt
	c.execute("1")     // toggle on
	c.execute("1")     // toggle off
	c.execute("")      // start with no focus
	if len(c.Focused()) != 0 {
		t.Fatal("expected no focused tasks after toggle off")
	}
}

func TestControlResponseIncludesFocusLines(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add important")
	c.execute("start")
	c.execute("") // skip prompt
	c.execute(cmdTaskFocus1)
	resp := c.Execute("status")
	if len(resp.Focused) == 0 {
		t.Fatal("expected focused tasks in response")
	}
	if resp.Focused[0].Description != "important" {
		t.Fatalf("expected task description in focused tasks, got %v", resp.Focused)
	}
}

func TestControlResponseIncludesFocusPrompt(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add pick me")
	resp := c.Execute("start")
	if resp.FocusPrompt == "" {
		t.Fatal("expected focus prompt in response")
	}
	if !strings.Contains(resp.FocusPrompt, "pick me") {
		t.Fatalf("expected task in prompt, got %q", resp.FocusPrompt)
	}
}

func TestControlResponseNoFocusLinesWhenEmpty(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("start") // enters prompt even with no tasks
	c.execute("")      // skip prompt, start pomodoro
	resp := c.Execute("status")
	if len(resp.Focused) != 0 {
		t.Fatalf("expected no focused tasks, got %v", resp.Focused)
	}
}

func TestCancelFocusPromptDoesNotStart(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add something")
	c.execute("start") // enters focus prompt
	result := c.cancelFocusPrompt()
	if c.FocusPromptPending() {
		t.Fatal("expected prompt to be cancelled")
	}
	if c.timer.State() != engine.Idle {
		t.Fatalf("expected idle after cancel, got %s", c.timer.State())
	}
	if !strings.Contains(result.message, "cancelled") {
		t.Fatalf("expected cancelled message, got %q", result.message)
	}
}

func TestCancelFocusPromptClearsPendingState(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add something")
	c.execute("start") // enters prompt
	c.execute("1")     // toggle a task
	c.cancelFocusPrompt()
	if c.pendingFocusToggled != nil {
		t.Fatal("expected toggled state cleared")
	}
	if c.pendingFocusAction != "" {
		t.Fatal("expected action cleared")
	}
}

func TestFocusPromptHintMentionsEsc(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add check hint")
	c.execute("start")
	prompt := c.FocusPrompt()
	if !strings.Contains(prompt, "esc") {
		t.Fatalf("expected 'esc' in prompt hint, got %q", prompt)
	}
}

func TestConfirmToWorkSkipsFocusPromptWhenFocusedTasksExist(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add task A")
	c.execute("task add task B")

	// Start pomodoro, select tasks 1 and 2 via focus prompt
	c.execute("start") // enters focus prompt
	c.execute("1")     // toggle task A
	c.execute("2")     // toggle task B
	c.execute("")      // confirm and start pomodoro

	// Complete task A (position 1 in active list)
	c.execute(cmdTaskDone1)

	// focused should still have task B
	if len(c.Focused()) != 1 {
		t.Fatalf("expected 1 focused task, got %d", len(c.Focused()))
	}

	// Complete work period, confirm into break
	c.timer.CompletePeriod()
	c.execute("confirm")

	// Complete break, confirm into work
	c.timer.CompletePeriod()
	c.execute("confirm")

	// Should NOT show focus prompt — incomplete focused tasks carry over
	if c.FocusPromptPending() {
		t.Fatal("should skip focus prompt when incomplete focused tasks exist")
	}

	// Should be in pomodoro state
	if c.timer.State() != engine.Work {
		t.Fatalf("expected pomodoro, got %s", c.timer.State())
	}

	// Focused tasks should still contain task B
	focused := c.Focused()
	if len(focused) != 1 {
		t.Fatalf("expected 1 focused task carried over, got %d", len(focused))
	}
	if focused[0].Description != "task B" {
		t.Fatalf("expected 'task B', got %q", focused[0].Description)
	}
}
