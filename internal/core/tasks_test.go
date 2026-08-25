package core

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/task"
)

const (
	fmtUnexpectedErr    = "unexpected error: %v"
	cmdTaskList         = "task list"
	cmdTaskDone1        = "task done 1"
	cmdTaskCompleted    = "task completed"
	msgNoActiveTasks    = "no active tasks"
	cmdTaskAddImportant = "task add important work"
	cmdTaskFocus1       = "task focus 1"
)

func newTestCoreWithTasks(t *testing.T) *Core {
	t.Helper()
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	dir := t.TempDir()
	store, err := task.NewFileStore(filepath.Join(dir, "tasks.json"))
	if err != nil {
		t.Fatal(err)
	}
	c.tasks = store
	return c
}

func TestTaskAddCommand(t *testing.T) {
	c := newTestCoreWithTasks(t)
	result := c.execute("task add write unit tests")
	if result.err != nil {
		t.Fatalf(fmtUnexpectedErr, result.err)
	}
	if !strings.Contains(result.message, "added") {
		t.Fatalf("expected message to contain 'added', got %q", result.message)
	}
	if !strings.Contains(result.message, "write unit tests") {
		t.Fatalf("expected message to contain description, got %q", result.message)
	}
}

func TestTaskListCommand(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add first task")
	c.execute("task add second task")
	result := c.execute(cmdTaskList)
	if result.err != nil {
		t.Fatalf(fmtUnexpectedErr, result.err)
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
	c := newTestCoreWithTasks(t)
	result := c.execute(cmdTaskList)
	if result.err != nil {
		t.Fatalf(fmtUnexpectedErr, result.err)
	}
	if !strings.Contains(result.message, msgNoActiveTasks) {
		t.Fatalf("expected 'no active tasks', got %q", result.message)
	}
}

func TestTaskDoneCommand(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add my task")
	result := c.execute(cmdTaskDone1)
	if result.err != nil {
		t.Fatalf(fmtUnexpectedErr, result.err)
	}
	if !strings.Contains(result.message, "completed") {
		t.Fatalf("expected message to contain 'completed', got %q", result.message)
	}
	list := c.execute(cmdTaskList)
	if !strings.Contains(list.message, msgNoActiveTasks) {
		t.Fatalf("expected no active tasks after done, got %q", list.message)
	}
}

func TestTaskCompletedCommand(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add finished task")
	c.execute(cmdTaskDone1)
	result := c.execute(cmdTaskCompleted)
	if result.err != nil {
		t.Fatalf(fmtUnexpectedErr, result.err)
	}
	if !strings.Contains(result.message, "finished task") {
		t.Fatalf("expected 'finished task' in completed list, got %q", result.message)
	}
	if !strings.Contains(result.message, "[done]") {
		t.Fatalf("expected '[done]' marker in completed list, got %q", result.message)
	}
}

func TestTaskCompletedEmptyCommand(t *testing.T) {
	c := newTestCoreWithTasks(t)
	result := c.execute(cmdTaskCompleted)
	if result.err != nil {
		t.Fatalf(fmtUnexpectedErr, result.err)
	}
	if !strings.Contains(result.message, "no completed tasks") {
		t.Fatalf("expected 'no completed tasks', got %q", result.message)
	}
}

func TestTaskRemoveCommand(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add removable task")
	result := c.execute("task remove 1")
	if result.err != nil {
		t.Fatalf(fmtUnexpectedErr, result.err)
	}
	if !strings.Contains(result.message, "removed") {
		t.Fatalf("expected message to contain 'removed', got %q", result.message)
	}
	list := c.execute(cmdTaskList)
	if !strings.Contains(list.message, msgNoActiveTasks) {
		t.Fatalf("expected no active tasks after remove, got %q", list.message)
	}
}

func TestTaskClearCommand(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add clear me")
	c.execute(cmdTaskDone1)
	result := c.execute("task clear")
	if result.err != nil {
		t.Fatalf(fmtUnexpectedErr, result.err)
	}
	if !strings.Contains(result.message, "cleared") {
		t.Fatalf("expected message to contain 'cleared', got %q", result.message)
	}
	completed := c.execute(cmdTaskCompleted)
	if !strings.Contains(completed.message, "no completed tasks") {
		t.Fatalf("expected no completed tasks after clear, got %q", completed.message)
	}
}

func TestTaskCommandWithoutStore(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	result := c.execute(cmdTaskList)
	if result.err == nil {
		t.Fatal("expected error when task store is nil")
	}
}

func TestTaskUnknownSubcommand(t *testing.T) {
	c := newTestCoreWithTasks(t)
	result := c.execute("task bogus")
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
	c := newCore(cfg, noopNotifier{})
	dir := t.TempDir()
	if err := c.initTasks(filepath.Join(dir, "tasks.json")); err != nil {
		t.Fatalf("initTasks: %v", err)
	}
	result := c.execute("task add test")
	if result.err != nil {
		t.Fatalf("task add after initTasks failed: %v", result.err)
	}
	if !strings.Contains(result.message, "added") {
		t.Fatalf("expected 'added' in message, got %q", result.message)
	}
}

// --- Task 9: Focus state tests ---

func TestTaskDoneDuringWorkSessionRemovesFromFocus(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add finish this")
	c.execute("start") // enters focus prompt
	c.execute("")      // skip prompt, start pomodoro
	c.execute(cmdTaskFocus1)
	c.execute(cmdTaskDone1)
	if len(c.Focused()) != 0 {
		t.Fatal("expected task removed from focus after done")
	}
}

// --- Task 10: Focus prompt state tests ---

// --- Task 11: Focus display in Response tests ---

func TestTaskRemoveDuringWorkSessionRemovesFromFocus(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add removable")
	c.execute("start") // enters focus prompt
	c.execute("1")     // toggle task
	c.execute("")      // confirm, start pomodoro
	if len(c.Focused()) != 1 {
		t.Fatal("expected 1 focused task before remove")
	}
	c.execute("task remove 1")
	if len(c.Focused()) != 0 {
		t.Fatal("expected task removed from focus after task remove")
	}
}

func TestHelpIncludesTaskCommands(t *testing.T) {
	help := Help()
	subcommands := []string{
		"task add",
		"task done",
		"task remove",
		cmdTaskList,
		cmdTaskCompleted,
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

func TestTasksListsActiveAndCompleted(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add first")
	c.execute("task add second")
	c.execute("task done 1")

	list := c.Tasks()
	if len(list.Active) != 1 || list.Active[0].Description != "second" {
		t.Fatalf("active = %+v", list.Active)
	}
	if len(list.Completed) != 1 || list.Completed[0].Description != "first" {
		t.Fatalf("completed = %+v", list.Completed)
	}
}
