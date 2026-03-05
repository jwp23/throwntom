package main

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/jwp23/throwntom/internal/config"
	"github.com/jwp23/throwntom/internal/task"
)

type noopNotifier struct{}

func (noopNotifier) PlaySound(string) error {
	return nil
}

func TestNewDaemonCoreDefaultsMorningPendingTrue(t *testing.T) {
	core := newDaemonCore(config.Default(), noopNotifier{})
	if !core.state.isMorningPending() {
		t.Fatal("expected morning reminder pending by default")
	}
}

func TestNewDaemonCoreRespectsMorningReminderPendingFalse(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false

	core := newDaemonCore(cfg, noopNotifier{})
	if core.state.isMorningPending() {
		t.Fatal("expected morning reminder pending to be false")
	}
}

func TestBeginMorningLoopStartsWhenPendingTrue(t *testing.T) {
	state := &daemonState{morningPending: true}
	ctx, started := state.beginMorningLoop()
	if !started {
		t.Fatal("expected beginMorningLoop to start when morningPending is true but no loop running")
	}
	if ctx == nil {
		t.Fatal("expected non-nil context")
	}
	// Clean up
	state.stopMorningLoop()
}

func TestBeginMorningLoopRejectsDuplicateLoop(t *testing.T) {
	state := &daemonState{}
	ctx, started := state.beginMorningLoop()
	if !started {
		t.Fatal("expected first beginMorningLoop to start")
	}
	if ctx == nil {
		t.Fatal("expected non-nil context from first call")
	}

	_, startedAgain := state.beginMorningLoop()
	if startedAgain {
		t.Fatal("expected second beginMorningLoop to be rejected (duplicate prevention)")
	}
	// Clean up
	state.stopMorningLoop()
}

func TestNewCycleCommandResetsCycleProgressButKeepsDailyTotal(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newDaemonCore(cfg, noopNotifier{})

	core.execute("start")
	core.cycle.CompletePeriod()
	before, _ := core.snapshot()
	if !strings.Contains(before, "today's pomodoros=1") {
		t.Fatalf("expected baseline daily total, got %s", before)
	}

	result := core.execute("new-cycle")
	if result.err != nil {
		t.Fatalf("new-cycle command failed: %v", result.err)
	}

	after, _ := core.snapshot()
	if !strings.Contains(after, "pomodoro") {
		t.Fatalf("expected pomodoro state, got %s", after)
	}
	if !strings.Contains(after, "pomodoros=0/4") {
		t.Fatalf("expected cycle reset, got %s", after)
	}
	if !strings.Contains(after, "today's pomodoros=1") {
		t.Fatalf("expected daily total preserved, got %s", after)
	}
}

// --- Task 6, 7, 8 Tests ---

func newTestCoreWithTasks(t *testing.T) *daemonCore {
	t.Helper()
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newDaemonCore(cfg, noopNotifier{})
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
	core := newDaemonCore(cfg, noopNotifier{})
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

// Task 7: initTasks wiring test
func TestInitTasksCreatesStore(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newDaemonCore(cfg, noopNotifier{})
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

// Task 8: help menu tests
func TestHelpIncludesTaskCommands(t *testing.T) {
	help := daemonCommandsHelp()
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
