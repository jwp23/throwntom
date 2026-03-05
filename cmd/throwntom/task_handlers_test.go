package main

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v2/internal/config"
	"github.com/jwp23/throwntom/v2/internal/task"
)

func newTestCoreWithTasks(t *testing.T) *timerCore {
	t.Helper()
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	dir := t.TempDir()
	store, err := task.NewFileStore(filepath.Join(dir, "tasks.json"))
	if err != nil {
		t.Fatal(err)
	}
	core.tasks = store
	return core
}

func TestTaskAddCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	result := core.execute("task add write unit tests")
	if result.err != nil {
		t.Fatalf("unexpected error: %v", result.err)
	}
	if !strings.Contains(result.message, "added") {
		t.Fatalf("expected message to contain 'added', got %q", result.message)
	}
	if !strings.Contains(result.message, "write unit tests") {
		t.Fatalf("expected message to contain description, got %q", result.message)
	}
}

func TestTaskListCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add first task")
	core.execute("task add second task")
	result := core.execute("task list")
	if result.err != nil {
		t.Fatalf("unexpected error: %v", result.err)
	}
	if !strings.Contains(result.message, "1)") {
		t.Fatalf("expected numbered list with '1)', got %q", result.message)
	}
	if !strings.Contains(result.message, "2)") {
		t.Fatalf("expected numbered list with '2)', got %q", result.message)
	}
	if !strings.Contains(result.message, "first task") {
		t.Fatalf("expected 'first task' in list, got %q", result.message)
	}
	if !strings.Contains(result.message, "second task") {
		t.Fatalf("expected 'second task' in list, got %q", result.message)
	}
}

func TestTaskListEmptyCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	result := core.execute("task list")
	if result.err != nil {
		t.Fatalf("unexpected error: %v", result.err)
	}
	if !strings.Contains(result.message, "no active tasks") {
		t.Fatalf("expected 'no active tasks', got %q", result.message)
	}
}

func TestTaskDoneCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add my task")
	result := core.execute("task done 1")
	if result.err != nil {
		t.Fatalf("unexpected error: %v", result.err)
	}
	if !strings.Contains(result.message, "completed") {
		t.Fatalf("expected message to contain 'completed', got %q", result.message)
	}
	list := core.execute("task list")
	if !strings.Contains(list.message, "no active tasks") {
		t.Fatalf("expected no active tasks after done, got %q", list.message)
	}
}

func TestTaskCompletedCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add finished task")
	core.execute("task done 1")
	result := core.execute("task completed")
	if result.err != nil {
		t.Fatalf("unexpected error: %v", result.err)
	}
	if !strings.Contains(result.message, "finished task") {
		t.Fatalf("expected 'finished task' in completed list, got %q", result.message)
	}
	if !strings.Contains(result.message, "[done]") {
		t.Fatalf("expected '[done]' marker in completed list, got %q", result.message)
	}
}

func TestTaskCompletedEmptyCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	result := core.execute("task completed")
	if result.err != nil {
		t.Fatalf("unexpected error: %v", result.err)
	}
	if !strings.Contains(result.message, "no completed tasks") {
		t.Fatalf("expected 'no completed tasks', got %q", result.message)
	}
}

func TestTaskRemoveCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add removable task")
	result := core.execute("task remove 1")
	if result.err != nil {
		t.Fatalf("unexpected error: %v", result.err)
	}
	if !strings.Contains(result.message, "removed") {
		t.Fatalf("expected message to contain 'removed', got %q", result.message)
	}
	list := core.execute("task list")
	if !strings.Contains(list.message, "no active tasks") {
		t.Fatalf("expected no active tasks after remove, got %q", list.message)
	}
}

func TestTaskClearCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add clear me")
	core.execute("task done 1")
	result := core.execute("task clear")
	if result.err != nil {
		t.Fatalf("unexpected error: %v", result.err)
	}
	if !strings.Contains(result.message, "cleared") {
		t.Fatalf("expected message to contain 'cleared', got %q", result.message)
	}
	completed := core.execute("task completed")
	if !strings.Contains(completed.message, "no completed tasks") {
		t.Fatalf("expected no completed tasks after clear, got %q", completed.message)
	}
}

func TestTaskCommandWithoutStore(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	result := core.execute("task list")
	if result.err == nil {
		t.Fatal("expected error when task store is nil")
	}
}

func TestTaskUnknownSubcommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	result := core.execute("task bogus")
	if result.err == nil {
		t.Fatal("expected error for unknown subcommand")
	}
	if !strings.Contains(result.err.Error(), "unknown task subcommand") {
		t.Fatalf("expected 'unknown task subcommand' error, got %q", result.err.Error())
	}
}

func TestInitTasksCreatesStore(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	dir := t.TempDir()
	if err := core.initTasks(filepath.Join(dir, "tasks.json")); err != nil {
		t.Fatalf("initTasks: %v", err)
	}
	result := core.execute("task add test")
	if result.err != nil {
		t.Fatalf("task add after initTasks failed: %v", result.err)
	}
	if !strings.Contains(result.message, "added") {
		t.Fatalf("expected 'added' in message, got %q", result.message)
	}
}

// --- Task 9: Focus state tests ---

func TestTaskFocusDuringWorkSession(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add important work")
	core.execute("start") // enters focus prompt
	core.execute("")      // skip prompt, start pomodoro
	result := core.execute("task focus 1")
	if result.err != nil {
		t.Fatalf("focus failed: %v", result.err)
	}
	focused := core.focusedTasks()
	if len(focused) != 1 {
		t.Fatalf("expected 1 focused, got %d", len(focused))
	}
	if focused[0].Description != "important work" {
		t.Fatalf("expected 'important work', got %q", focused[0].Description)
	}
}

func TestTaskFocusRejectsOutsideWorkSession(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add important work")
	result := core.execute("task focus 1")
	if result.err == nil {
		t.Fatal("expected error when not in work session")
	}
}

func TestTaskUnfocus(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add important work")
	core.execute("start") // enters focus prompt
	core.execute("")      // skip prompt, start pomodoro
	core.execute("task focus 1")
	result := core.execute("task unfocus 1")
	if result.err != nil {
		t.Fatal(result.err)
	}
	if len(core.focusedTasks()) != 0 {
		t.Fatal("expected empty focused list after unfocus")
	}
}

func TestTaskUpDown(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add first")
	core.execute("task add second")
	core.execute("start") // enters focus prompt
	core.execute("")      // skip prompt, start pomodoro
	core.execute("task focus 1")
	core.execute("task focus 2")
	core.execute("task up 2")
	focused := core.focusedTasks()
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

func TestFocusClearedOnStop(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add work item")
	core.execute("start") // enters focus prompt
	core.execute("")      // skip prompt, start pomodoro
	core.execute("task focus 1")
	core.execute("stop")
	if len(core.focusedTasks()) != 0 {
		t.Fatal("expected focus cleared on stop")
	}
}

func TestTaskDoneDuringWorkSessionRemovesFromFocus(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add finish this")
	core.execute("start") // enters focus prompt
	core.execute("")      // skip prompt, start pomodoro
	core.execute("task focus 1")
	core.execute("task done 1")
	if len(core.focusedTasks()) != 0 {
		t.Fatal("expected task removed from focus after done")
	}
}

// --- Task 10: Focus prompt state tests ---

func TestStartEntersFocusPromptWhenTasksExist(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add something to do")
	result := core.execute("start")
	if !core.isFocusPromptPending() {
		t.Fatal("expected focus prompt to be pending")
	}
	if !strings.Contains(result.message, "Select tasks") {
		t.Fatalf("expected prompt message, got %q", result.message)
	}
	if core.cycle.Status() != "idle" {
		t.Fatalf("expected idle during prompt, got %s", core.cycle.Status())
	}
}

func TestStartShowsPromptWhenNoTasks(t *testing.T) {
	core := newTestCoreWithTasks(t)
	result := core.execute("start")
	if !core.isFocusPromptPending() {
		t.Fatal("expected focus prompt even when no tasks exist")
	}
	if !strings.Contains(result.message, "Select tasks") {
		t.Fatalf("expected prompt message, got %q", result.message)
	}
	if core.cycle.Status() != "idle" {
		t.Fatalf("expected idle during prompt, got %s", core.cycle.Status())
	}
}

func TestStartPromptEmptyListAllowsAddAndStart(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("start") // enters prompt even with no tasks
	core.execute("a new task from prompt")
	result := core.execute("") // confirm
	if core.isFocusPromptPending() {
		t.Fatal("expected prompt cleared")
	}
	if core.cycle.Status() != "pomodoro" {
		t.Fatalf("expected pomodoro, got %s", core.cycle.Status())
	}
	focused := core.focusedTasks()
	if len(focused) != 1 {
		t.Fatalf("expected 1 focused, got %d", len(focused))
	}
	if focused[0].Description != "new task from prompt" {
		t.Fatalf("expected 'new task from prompt', got %q", focused[0].Description)
	}
	_ = result
}

func TestStartPromptEmptyListSkipStarts(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("start") // enters prompt even with no tasks
	core.execute("")      // skip with no tasks
	if core.isFocusPromptPending() {
		t.Fatal("expected prompt cleared")
	}
	if core.cycle.Status() != "pomodoro" {
		t.Fatalf("expected pomodoro, got %s", core.cycle.Status())
	}
	if len(core.focusedTasks()) != 0 {
		t.Fatal("expected no focused tasks after skip")
	}
}

func TestFocusPromptToggleAndStart(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add first task")
	core.execute("task add second task")
	core.execute("start")       // enters prompt
	result := core.execute("1") // toggle task 1
	if !strings.Contains(result.message, "Focused") {
		t.Fatalf("expected focused info, got %q", result.message)
	}
	result = core.execute("") // empty enter = confirm and start
	if core.isFocusPromptPending() {
		t.Fatal("expected prompt cleared")
	}
	if core.cycle.Status() != "pomodoro" {
		t.Fatalf("expected pomodoro, got %s", core.cycle.Status())
	}
	focused := core.focusedTasks()
	if len(focused) != 1 {
		t.Fatalf("expected 1 focused, got %d", len(focused))
	}
	if focused[0].Description != "first task" {
		t.Fatalf("expected 'first task', got %q", focused[0].Description)
	}
}

func TestFocusPromptSkip(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add something")
	core.execute("start") // enters prompt
	core.execute("")      // skip (empty with no toggles)
	if core.isFocusPromptPending() {
		t.Fatal("expected prompt cleared")
	}
	if core.cycle.Status() != "pomodoro" {
		t.Fatalf("expected pomodoro, got %s", core.cycle.Status())
	}
	if len(core.focusedTasks()) != 0 {
		t.Fatal("expected no focused tasks after skip")
	}
}

func TestFocusPromptAddNewTask(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add existing")
	core.execute("start") // enters prompt
	result := core.execute("a brand new task")
	if !strings.Contains(result.message, "brand new task") {
		t.Fatalf("expected task in prompt, got %q", result.message)
	}
	active := core.tasks.Active()
	if len(active) != 2 {
		t.Fatalf("expected 2 active tasks, got %d", len(active))
	}
}

func TestConfirmToWorkTriggersFocusPrompt(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add keep working")
	core.execute("start")       // prompt
	core.execute("")            // skip prompt, start pomodoro
	core.cycle.CompletePeriod() // work done -> awaiting confirm
	core.execute("confirm")     // -> short break (no prompt for breaks)
	if core.isFocusPromptPending() {
		t.Fatal("should not prompt for break")
	}
	core.cycle.CompletePeriod() // break done -> awaiting confirm
	core.execute("confirm")     // -> work (should trigger prompt)
	if !core.isFocusPromptPending() {
		t.Fatal("expected focus prompt when confirming into work phase")
	}
}

func TestFocusPromptToggleOff(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add toggleable")
	core.execute("start") // enters prompt
	core.execute("1")     // toggle on
	core.execute("1")     // toggle off
	core.execute("")      // start with no focus
	if len(core.focusedTasks()) != 0 {
		t.Fatal("expected no focused tasks after toggle off")
	}
}

// --- Task 11: Focus display in commandResponse tests ---

func TestControlResponseIncludesFocusLines(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add important")
	core.execute("start")
	core.execute("") // skip prompt
	core.execute("task focus 1")
	resp := core.executeCommand("status")
	if len(resp.FocusLines) == 0 {
		t.Fatal("expected focus lines in response")
	}
	found := false
	for _, line := range resp.FocusLines {
		if strings.Contains(line, "important") {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("expected task description in focus lines, got %v", resp.FocusLines)
	}
}

func TestControlResponseIncludesFocusPrompt(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add pick me")
	resp := core.executeCommand("start")
	if resp.FocusPrompt == "" {
		t.Fatal("expected focus prompt in response")
	}
	if !strings.Contains(resp.FocusPrompt, "pick me") {
		t.Fatalf("expected task in prompt, got %q", resp.FocusPrompt)
	}
}

func TestControlResponseNoFocusLinesWhenEmpty(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("start") // enters prompt even with no tasks
	core.execute("")      // skip prompt, start pomodoro
	resp := core.executeCommand("status")
	if len(resp.FocusLines) != 0 {
		t.Fatalf("expected no focus lines, got %v", resp.FocusLines)
	}
}

func TestCancelFocusPromptDoesNotStart(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add something")
	core.execute("start") // enters focus prompt
	result := core.cancelFocusPrompt()
	if core.isFocusPromptPending() {
		t.Fatal("expected prompt to be cancelled")
	}
	if core.cycle.Status() != "idle" {
		t.Fatalf("expected idle after cancel, got %s", core.cycle.Status())
	}
	if !strings.Contains(result.message, "cancelled") {
		t.Fatalf("expected cancelled message, got %q", result.message)
	}
}

func TestCancelFocusPromptClearsPendingState(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add something")
	core.execute("start") // enters prompt
	core.execute("1")     // toggle a task
	core.cancelFocusPrompt()
	if core.pendingFocusToggled != nil {
		t.Fatal("expected toggled state cleared")
	}
	if core.pendingFocusAction != "" {
		t.Fatal("expected action cleared")
	}
}

func TestFocusPromptHintMentionsEsc(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add check hint")
	core.execute("start")
	prompt := core.formatFocusPrompt()
	if !strings.Contains(prompt, "esc") {
		t.Fatalf("expected 'esc' in prompt hint, got %q", prompt)
	}
}

func TestHelpIncludesTaskCommands(t *testing.T) {
	help := commandsHelp()
	subcommands := []string{
		"task add",
		"task done",
		"task remove",
		"task list",
		"task completed",
		"task clear",
		"task focus",
		"task unfocus",
		"task up",
		"task down",
	}
	for _, sub := range subcommands {
		if !strings.Contains(help, sub) {
			t.Errorf("help text missing %q", sub)
		}
	}
}
