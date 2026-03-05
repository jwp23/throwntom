# Focused Tasks Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a lightweight task list with per-pomodoro focus selection to the throwntom CLI.

**Architecture:** New `internal/task` package with a `Store` interface and `FileStore` implementation for JSON persistence. The `App` layer tracks focused tasks per pomodoro. Daemon core dispatches `task *` commands and orchestrates the focus prompt. The Bubble Tea UI renders the focus display and prompt.

**Tech Stack:** Go standard library (encoding/json, os, time). No new dependencies.

---

### Task 1: `internal/task` — Data Types and Store Interface

**Files:**
- Create: `internal/task/task.go`
- Test: `internal/task/task_test.go`

**Step 1: Write failing test for Task struct and Store interface**

```go
// internal/task/task_test.go
package task

import "testing"

func TestTaskHasRequiredFields(t *testing.T) {
	tk := Task{ID: 1, Description: "test task"}
	if tk.ID != 1 {
		t.Fatal("expected ID 1")
	}
	if tk.Description != "test task" {
		t.Fatal("expected description")
	}
	if tk.Done {
		t.Fatal("expected not done by default")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./internal/task/`
Expected: FAIL — package does not exist

**Step 3: Write minimal implementation**

```go
// internal/task/task.go
package task

import "time"

type Task struct {
	ID          int       `json:"id"`
	Description string    `json:"description"`
	Done        bool      `json:"done"`
	CreatedAt   time.Time `json:"created_at"`
	CompletedAt time.Time `json:"completed_at,omitempty"`
}

type Store interface {
	Add(description string) (Task, error)
	Complete(id int) error
	Remove(id int) error
	Active() []Task
	Completed() []Task
	ClearCompleted() error
}
```

**Step 4: Run test to verify it passes**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./internal/task/`
Expected: PASS

**Step 5: Commit**

```
test: add task data type test
feat: add task package with Store interface and Task type
```

---

### Task 2: `internal/task` — FileStore Add and Active

**Files:**
- Create: `internal/task/file_store.go`
- Modify: `internal/task/task_test.go`

**Step 1: Write failing tests**

```go
func TestFileStoreAddCreatesTask(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tasks.json")
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	tk, err := store.Add("write tests")
	if err != nil {
		t.Fatal(err)
	}
	if tk.ID != 1 {
		t.Fatalf("expected ID 1, got %d", tk.ID)
	}
	if tk.Description != "write tests" {
		t.Fatalf("expected description 'write tests', got %q", tk.Description)
	}
	if tk.Done {
		t.Fatal("expected not done")
	}
	if tk.CreatedAt.IsZero() {
		t.Fatal("expected non-zero created_at")
	}
}

func TestFileStoreActiveReturnsUncompleted(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tasks.json")
	store, _ := NewFileStore(path)
	store.Add("task one")
	store.Add("task two")
	active := store.Active()
	if len(active) != 2 {
		t.Fatalf("expected 2 active tasks, got %d", len(active))
	}
}

func TestFileStoreIDsAutoIncrement(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tasks.json")
	store, _ := NewFileStore(path)
	t1, _ := store.Add("first")
	t2, _ := store.Add("second")
	if t2.ID != t1.ID+1 {
		t.Fatalf("expected sequential IDs, got %d and %d", t1.ID, t2.ID)
	}
}
```

**Step 2: Run test to verify they fail**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./internal/task/`
Expected: FAIL — `NewFileStore` undefined

**Step 3: Write minimal implementation**

```go
// internal/task/file_store.go
package task

import (
	"encoding/json"
	"fmt"
	"os"
	"time"
)

type fileData struct {
	NextID int    `json:"next_id"`
	Tasks  []Task `json:"tasks"`
}

type FileStore struct {
	path string
	data fileData
}

func NewFileStore(path string) (*FileStore, error) {
	s := &FileStore{path: path, data: fileData{NextID: 1}}
	if err := s.load(); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *FileStore) Add(description string) (Task, error) {
	tk := Task{
		ID:          s.data.NextID,
		Description: description,
		CreatedAt:   time.Now(),
	}
	s.data.NextID++
	s.data.Tasks = append(s.data.Tasks, tk)
	if err := s.save(); err != nil {
		return Task{}, err
	}
	return tk, nil
}

func (s *FileStore) Active() []Task {
	var active []Task
	for _, tk := range s.data.Tasks {
		if !tk.Done {
			active = append(active, tk)
		}
	}
	return active
}

func (s *FileStore) Complete(id int) error   { return fmt.Errorf("not implemented") }
func (s *FileStore) Remove(id int) error     { return fmt.Errorf("not implemented") }
func (s *FileStore) Completed() []Task       { return nil }
func (s *FileStore) ClearCompleted() error   { return fmt.Errorf("not implemented") }

func (s *FileStore) load() error {
	b, err := os.ReadFile(s.path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("read tasks file: %w", err)
	}
	if err := json.Unmarshal(b, &s.data); err != nil {
		return fmt.Errorf("parse tasks file: %w", err)
	}
	return nil
}

func (s *FileStore) save() error {
	b, err := json.MarshalIndent(s.data, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal tasks: %w", err)
	}
	return os.WriteFile(s.path, b, 0o644)
}
```

**Step 4: Run test to verify they pass**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./internal/task/`
Expected: PASS

**Step 5: Commit**

```
test: add FileStore Add and Active tests
feat: implement FileStore with Add, Active, and JSON persistence
```

---

### Task 3: `internal/task` — FileStore Complete, Remove, Completed, ClearCompleted

**Files:**
- Modify: `internal/task/file_store.go`
- Modify: `internal/task/task_test.go`

**Step 1: Write failing tests**

```go
func TestFileStoreCompleteMarksTaskDone(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewFileStore(filepath.Join(dir, "tasks.json"))
	tk, _ := store.Add("do thing")
	if err := store.Complete(tk.ID); err != nil {
		t.Fatal(err)
	}
	active := store.Active()
	if len(active) != 0 {
		t.Fatalf("expected 0 active, got %d", len(active))
	}
	completed := store.Completed()
	if len(completed) != 1 {
		t.Fatalf("expected 1 completed, got %d", len(completed))
	}
	if completed[0].CompletedAt.IsZero() {
		t.Fatal("expected non-zero completed_at")
	}
}

func TestFileStoreCompleteUnknownIDReturnsError(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewFileStore(filepath.Join(dir, "tasks.json"))
	if err := store.Complete(999); err == nil {
		t.Fatal("expected error for unknown ID")
	}
}

func TestFileStoreRemoveDeletesTask(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewFileStore(filepath.Join(dir, "tasks.json"))
	tk, _ := store.Add("remove me")
	if err := store.Remove(tk.ID); err != nil {
		t.Fatal(err)
	}
	if len(store.Active()) != 0 {
		t.Fatal("expected empty active list after remove")
	}
}

func TestFileStoreClearCompletedRemovesDoneTasks(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewFileStore(filepath.Join(dir, "tasks.json"))
	tk, _ := store.Add("done task")
	store.Add("active task")
	store.Complete(tk.ID)
	if err := store.ClearCompleted(); err != nil {
		t.Fatal(err)
	}
	if len(store.Completed()) != 0 {
		t.Fatal("expected no completed tasks after clear")
	}
	if len(store.Active()) != 1 {
		t.Fatal("expected 1 active task after clear")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s -run "TestFileStore(Complete|Remove|ClearCompleted)" ./internal/task/`
Expected: FAIL — "not implemented"

**Step 3: Implement Complete, Remove, Completed, ClearCompleted**

Replace the stub methods in `file_store.go`:

```go
func (s *FileStore) Complete(id int) error {
	for i := range s.data.Tasks {
		if s.data.Tasks[i].ID == id {
			if s.data.Tasks[i].Done {
				return fmt.Errorf("task %d already completed", id)
			}
			s.data.Tasks[i].Done = true
			s.data.Tasks[i].CompletedAt = time.Now()
			return s.save()
		}
	}
	return fmt.Errorf("task %d not found", id)
}

func (s *FileStore) Remove(id int) error {
	for i, tk := range s.data.Tasks {
		if tk.ID == id {
			s.data.Tasks = append(s.data.Tasks[:i], s.data.Tasks[i+1:]...)
			return s.save()
		}
	}
	return fmt.Errorf("task %d not found", id)
}

func (s *FileStore) Completed() []Task {
	var done []Task
	for _, tk := range s.data.Tasks {
		if tk.Done {
			done = append(done, tk)
		}
	}
	return done
}

func (s *FileStore) ClearCompleted() error {
	var kept []Task
	for _, tk := range s.data.Tasks {
		if !tk.Done {
			kept = append(kept, tk)
		}
	}
	s.data.Tasks = kept
	return s.save()
}
```

**Step 4: Run tests to verify they pass**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./internal/task/`
Expected: PASS

**Step 5: Commit**

```
test: add Complete, Remove, Completed, ClearCompleted tests
feat: implement remaining FileStore methods
```

---

### Task 4: `internal/task` — FileStore Persistence Across Loads

**Files:**
- Modify: `internal/task/task_test.go`

**Step 1: Write failing test for persistence**

```go
func TestFileStorePersistsAcrossLoads(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tasks.json")
	store1, _ := NewFileStore(path)
	store1.Add("persist me")
	store1.Add("complete me")
	store1.Complete(2)

	store2, err := NewFileStore(path)
	if err != nil {
		t.Fatal(err)
	}
	active := store2.Active()
	if len(active) != 1 {
		t.Fatalf("expected 1 active after reload, got %d", len(active))
	}
	if active[0].Description != "persist me" {
		t.Fatalf("expected 'persist me', got %q", active[0].Description)
	}
	completed := store2.Completed()
	if len(completed) != 1 {
		t.Fatalf("expected 1 completed after reload, got %d", len(completed))
	}
}

func TestFileStoreNextIDSurvivesReload(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "tasks.json")
	store1, _ := NewFileStore(path)
	store1.Add("first")

	store2, _ := NewFileStore(path)
	tk, _ := store2.Add("second")
	if tk.ID != 2 {
		t.Fatalf("expected ID 2 after reload, got %d", tk.ID)
	}
}
```

**Step 2: Run tests — these should already pass if save/load work correctly**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s -run "TestFileStore(Persist|NextID)" ./internal/task/`
Expected: PASS (validates save/load round-trip)

**Step 3: Commit**

```
test: add persistence round-trip tests for FileStore
```

---

### Task 5: `internal/task` — Position-to-ID Mapping Helper

**Files:**
- Modify: `internal/task/file_store.go`
- Modify: `internal/task/task_test.go`

The UI shows 1-based positions for active tasks. We need a helper to map position → ID.

**Step 1: Write failing test**

```go
func TestFileStoreActiveTaskID(t *testing.T) {
	dir := t.TempDir()
	store, _ := NewFileStore(filepath.Join(dir, "tasks.json"))
	store.Add("first")
	store.Add("second")
	store.Add("third")
	store.Complete(2) // "second" is done

	// Active list: [first(ID=1), third(ID=3)]
	id, err := store.ActiveTaskID(1) // position 1 = first
	if err != nil {
		t.Fatal(err)
	}
	if id != 1 {
		t.Fatalf("expected ID 1, got %d", id)
	}
	id, err = store.ActiveTaskID(2) // position 2 = third
	if err != nil {
		t.Fatal(err)
	}
	if id != 3 {
		t.Fatalf("expected ID 3, got %d", id)
	}
	_, err = store.ActiveTaskID(3) // out of range
	if err == nil {
		t.Fatal("expected error for out-of-range position")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s -run "TestFileStoreActiveTaskID" ./internal/task/`
Expected: FAIL — `ActiveTaskID` undefined

**Step 3: Write implementation**

```go
func (s *FileStore) ActiveTaskID(position int) (int, error) {
	active := s.Active()
	if position < 1 || position > len(active) {
		return 0, fmt.Errorf("position %d out of range (1-%d)", position, len(active))
	}
	return active[position-1].ID, nil
}
```

**Step 4: Run test to verify it passes**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./internal/task/`
Expected: PASS

**Step 5: Commit**

```
test: add ActiveTaskID position mapping test
feat: add ActiveTaskID for position-to-ID mapping
```

---

### Task 6: Daemon Core — Task Command Dispatch

**Files:**
- Modify: `cmd/throwntom/daemon_core.go` (add `task` handler + task store field)
- Modify: `cmd/throwntom/daemon_core_test.go`

**Step 1: Write failing tests**

```go
func TestTaskAddCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	result := core.execute("task add write unit tests")
	if result.err != nil {
		t.Fatalf("unexpected error: %v", result.err)
	}
	if !strings.Contains(result.message, "added") {
		t.Fatalf("expected 'added' message, got %q", result.message)
	}
}

func TestTaskListCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add first task")
	core.execute("task add second task")
	result := core.execute("task list")
	if result.err != nil {
		t.Fatal(result.err)
	}
	if !strings.Contains(result.message, "1)") || !strings.Contains(result.message, "first task") {
		t.Fatalf("expected numbered task list, got %q", result.message)
	}
}

func TestTaskDoneCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add finish this")
	result := core.execute("task done 1")
	if result.err != nil {
		t.Fatal(result.err)
	}
	list := core.execute("task list")
	if strings.Contains(list.message, "finish this") {
		t.Fatal("completed task should not appear in active list")
	}
}

func TestTaskCompletedCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add finish this")
	core.execute("task done 1")
	result := core.execute("task completed")
	if !strings.Contains(result.message, "finish this") {
		t.Fatalf("expected completed task in output, got %q", result.message)
	}
}

func TestTaskRemoveCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add remove me")
	result := core.execute("task remove 1")
	if result.err != nil {
		t.Fatal(result.err)
	}
	list := core.execute("task list")
	if strings.Contains(list.message, "remove me") {
		t.Fatal("removed task should not appear")
	}
}

func TestTaskClearCommand(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add done one")
	core.execute("task done 1")
	result := core.execute("task clear")
	if result.err != nil {
		t.Fatal(result.err)
	}
	completed := core.execute("task completed")
	if strings.Contains(completed.message, "done one") {
		t.Fatal("cleared task should not appear in completed")
	}
}

// Helper: creates a daemonCore with a task store in a temp directory
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
```

**Step 2: Run tests to verify they fail**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s -run "TestTask" ./cmd/throwntom/`
Expected: FAIL — `core.tasks` undefined, `task` not imported

**Step 3: Implement task command handler in daemon_core.go**

Add to `daemonCore` struct (line 94):
```go
tasks  *task.FileStore
```

Add import for `"github.com/jwp23/throwntom/internal/task"`.

Add to `buildCommandHandlers()` (line 173):
```go
"task": d.handleTask,
```

Add handler method:
```go
func (d *daemonCore) handleTask(parts []string) daemonCommandResult {
	if len(parts) < 2 {
		return daemonCommandResult{err: fmt.Errorf("usage: task <add|done|remove|list|completed|clear|focus|unfocus|up|down> [args]")}
	}
	if d.tasks == nil {
		return daemonCommandResult{err: fmt.Errorf("task store not available")}
	}
	sub := parts[1]
	args := parts[2:]
	switch sub {
	case "add":
		return d.handleTaskAdd(args)
	case "done":
		return d.handleTaskDone(args)
	case "remove":
		return d.handleTaskRemove(args)
	case "list":
		return d.handleTaskList()
	case "completed":
		return d.handleTaskCompleted()
	case "clear":
		return d.handleTaskClear()
	default:
		return daemonCommandResult{err: fmt.Errorf("unknown task subcommand: %s", sub)}
	}
}
```

Add subcommand handlers:
```go
func (d *daemonCore) handleTaskAdd(args []string) daemonCommandResult {
	if len(args) == 0 {
		return daemonCommandResult{err: fmt.Errorf("usage: task add <description>")}
	}
	desc := strings.Join(args, " ")
	tk, err := d.tasks.Add(desc)
	if err != nil {
		return daemonCommandResult{err: err}
	}
	return daemonCommandResult{message: fmt.Sprintf("added task %d: %s", tk.ID, tk.Description)}
}

func (d *daemonCore) handleTaskDone(args []string) daemonCommandResult {
	if len(args) < 1 {
		return daemonCommandResult{err: fmt.Errorf("usage: task done <number>")}
	}
	pos, err := strconv.Atoi(args[0])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid task number: %s", args[0])}
	}
	id, err := d.tasks.ActiveTaskID(pos)
	if err != nil {
		return daemonCommandResult{err: err}
	}
	if err := d.tasks.Complete(id); err != nil {
		return daemonCommandResult{err: err}
	}
	return daemonCommandResult{message: fmt.Sprintf("task %d completed", pos)}
}

func (d *daemonCore) handleTaskRemove(args []string) daemonCommandResult {
	if len(args) < 1 {
		return daemonCommandResult{err: fmt.Errorf("usage: task remove <number>")}
	}
	pos, err := strconv.Atoi(args[0])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid task number: %s", args[0])}
	}
	id, err := d.tasks.ActiveTaskID(pos)
	if err != nil {
		return daemonCommandResult{err: err}
	}
	if err := d.tasks.Remove(id); err != nil {
		return daemonCommandResult{err: err}
	}
	return daemonCommandResult{message: fmt.Sprintf("task %d removed", pos)}
}

func (d *daemonCore) handleTaskList() daemonCommandResult {
	active := d.tasks.Active()
	if len(active) == 0 {
		return daemonCommandResult{message: "no active tasks"}
	}
	var lines []string
	for i, tk := range active {
		lines = append(lines, fmt.Sprintf("  %d) %s", i+1, tk.Description))
	}
	return daemonCommandResult{message: strings.Join(lines, "\n")}
}

func (d *daemonCore) handleTaskCompleted() daemonCommandResult {
	done := d.tasks.Completed()
	if len(done) == 0 {
		return daemonCommandResult{message: "no completed tasks"}
	}
	var lines []string
	for _, tk := range done {
		lines = append(lines, fmt.Sprintf("  [done] %s (%s)", tk.Description, tk.CompletedAt.Format("15:04")))
	}
	return daemonCommandResult{message: strings.Join(lines, "\n")}
}

func (d *daemonCore) handleTaskClear() daemonCommandResult {
	if err := d.tasks.ClearCompleted(); err != nil {
		return daemonCommandResult{err: err}
	}
	return daemonCommandResult{message: "completed tasks cleared"}
}
```

**Step 4: Run tests to verify they pass**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./cmd/throwntom/`
Expected: PASS

**Step 5: Commit**

```
test: add task command dispatch tests
feat: add task command handler to daemon core
```

---

### Task 7: Task Store Wiring in Modes

**Files:**
- Modify: `cmd/throwntom/daemon_core.go` (newDaemonCore accepts task store path)
- Modify: `cmd/throwntom/main.go` (resolve tasks.json path)
- Modify: `cmd/throwntom/modes.go` (pass task path to daemon core)

**Step 1: Write failing test**

```go
func TestNewDaemonCoreWithTasksPath(t *testing.T) {
	dir := t.TempDir()
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newDaemonCore(cfg, noopNotifier{})
	if err := core.initTasks(filepath.Join(dir, "tasks.json")); err != nil {
		t.Fatal(err)
	}
	result := core.execute("task add test wiring")
	if result.err != nil {
		t.Fatalf("task add failed: %v", result.err)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s -run "TestNewDaemonCoreWithTasksPath" ./cmd/throwntom/`
Expected: FAIL — `initTasks` undefined

**Step 3: Add `initTasks` method and wire in modes**

In `daemon_core.go`, add:
```go
func (d *daemonCore) initTasks(path string) error {
	store, err := task.NewFileStore(path)
	if err != nil {
		return fmt.Errorf("init task store: %w", err)
	}
	d.tasks = store
	return nil
}
```

In `main.go`, add a `defaultTasksPath()` function:
```go
func defaultTasksPath() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home directory: %w", err)
	}
	return filepath.Join(homeDir, ".config", "throwntom", "tasks.json"), nil
}
```

In `modes.go`, update `buildDaemonCore()` (line 157) to also init tasks:
```go
func buildDaemonCore(cfg config.Config) (*daemonCore, error) {
	n, err := notifier.NewSystemNotifier(runtime.GOOS, os.Stdout, cfg.SoundCommand)
	if err != nil {
		return nil, err
	}
	core := newDaemonCore(cfg, n)
	tasksPath, err := defaultTasksPath()
	if err != nil {
		return nil, err
	}
	if err := core.initTasks(tasksPath); err != nil {
		return nil, err
	}
	return core, nil
}
```

**Step 4: Run tests to verify they pass**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./cmd/throwntom/`
Expected: PASS

**Step 5: Commit**

```
test: add task store wiring test
feat: wire task store into daemon core and modes
```

---

### Task 8: Help Menu — Add Task Commands

**Files:**
- Modify: `cmd/throwntom/daemon_core.go` (update `daemonCommandsHelp()`)
- Modify: `cmd/throwntom/daemon_core_test.go`

**Step 1: Write failing test**

```go
func TestHelpIncludesTaskCommands(t *testing.T) {
	help := daemonCommandsHelp()
	for _, cmd := range []string{"task add", "task done", "task remove", "task list", "task completed", "task clear", "task focus", "task unfocus", "task up", "task down"} {
		if !strings.Contains(help, cmd) {
			t.Fatalf("help missing %q", cmd)
		}
	}
}
```

**Step 2: Run test to verify it fails**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s -run "TestHelpIncludesTaskCommands" ./cmd/throwntom/`
Expected: FAIL — help text doesn't contain task commands

**Step 3: Update `daemonCommandsHelp()`**

In `daemon_core.go`, update the function at line 301:
```go
func daemonCommandsHelp() string {
	return strings.Join([]string{
		"daemon commands:",
		"  start              start a new pomodoro",
		"  new-cycle          start a fresh pomodoro cycle",
		"  pause              pause the active pomodoro or break timer",
		"  resume             resume a paused pomodoro or break timer",
		"  stop               stop active timer and return to idle",
		"  confirm            acknowledge transition and move to next phase",
		"  snooze <duration>  delay reminders (example: snooze 10m)",
		"  skip-today         disable reminders and cycle for the rest of today",
		"  status             print current cycle status",
		"  test-sound         play reminder sound now",
		"  quit               stop daemon",
		"  exit               alias for quit",
		"",
		"task commands:",
		"  task add <desc>     add a task",
		"  task done <n>       complete a task",
		"  task remove <n>     delete a task",
		"  task list           show active tasks",
		"  task completed      show completed tasks",
		"  task clear          clear completed tasks",
		"  task focus <n>      focus on a task (work session)",
		"  task unfocus <n>    remove focus (work session)",
		"  task up <n>         move focused task up",
		"  task down <n>       move focused task down",
	}, "\n")
}
```

**Step 4: Run tests to verify they pass**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./cmd/throwntom/`
Expected: PASS

**Step 5: Commit**

```
test: add help text coverage for task commands
feat: add task commands to help menu
```

---

### Task 9: Focus State in Daemon Core

**Files:**
- Modify: `cmd/throwntom/daemon_core.go` (add focus state, focus/unfocus/up/down handlers)
- Modify: `cmd/throwntom/daemon_core_test.go`

**Step 1: Write failing tests**

```go
func TestTaskFocusDuringWorkSession(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add important work")
	core.execute("start")
	result := core.execute("task focus 1")
	if result.err != nil {
		t.Fatalf("focus failed: %v", result.err)
	}
	focused := core.focusedTasks()
	if len(focused) != 1 {
		t.Fatalf("expected 1 focused, got %d", len(focused))
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
	core.execute("start")
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
	core.execute("start")
	core.execute("task focus 1")
	core.execute("task focus 2")
	core.execute("task up 2") // move "second" to position 1
	focused := core.focusedTasks()
	if focused[0].Description != "second" {
		t.Fatalf("expected 'second' at top, got %q", focused[0].Description)
	}
}

func TestFocusClearedOnStop(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add work item")
	core.execute("start")
	core.execute("task focus 1")
	core.execute("stop")
	if len(core.focusedTasks()) != 0 {
		t.Fatal("expected focus cleared on stop")
	}
}

func TestTaskDoneDuringWorkSessionRemovesFromFocus(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add finish this")
	core.execute("start")
	core.execute("task focus 1")
	core.execute("task done 1")
	if len(core.focusedTasks()) != 0 {
		t.Fatal("expected task removed from focus after done")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s -run "TestTask(Focus|Unfocus|UpDown|Done)" ./cmd/throwntom/`
Expected: FAIL — `focusedTasks` undefined

**Step 3: Implement focus state**

Add focus state to `daemonCore`:
```go
type daemonCore struct {
	// ... existing fields ...
	tasks   *task.FileStore
	focused []task.Task // current pomodoro's focused tasks, ordered by priority
}
```

Add public accessor:
```go
func (d *daemonCore) focusedTasks() []task.Task {
	return append([]task.Task(nil), d.focused...)
}
```

Add focus subcommands to `handleTask` switch:
```go
case "focus":
	return d.handleTaskFocus(args)
case "unfocus":
	return d.handleTaskUnfocus(args)
case "up":
	return d.handleTaskUp(args)
case "down":
	return d.handleTaskDown(args)
```

Implement handlers:
```go
func (d *daemonCore) isWorkSession() bool {
	return d.cycle.Status() == "pomodoro"
}

func (d *daemonCore) handleTaskFocus(args []string) daemonCommandResult {
	if !d.isWorkSession() {
		return daemonCommandResult{err: fmt.Errorf("focus is only available during a work session")}
	}
	if len(args) < 1 {
		return daemonCommandResult{err: fmt.Errorf("usage: task focus <number>")}
	}
	pos, err := strconv.Atoi(args[0])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid task number: %s", args[0])}
	}
	id, err := d.tasks.ActiveTaskID(pos)
	if err != nil {
		return daemonCommandResult{err: err}
	}
	for _, f := range d.focused {
		if f.ID == id {
			return daemonCommandResult{message: "task already focused"}
		}
	}
	active := d.tasks.Active()
	for _, tk := range active {
		if tk.ID == id {
			d.focused = append(d.focused, tk)
			return daemonCommandResult{message: fmt.Sprintf("focused on: %s", tk.Description)}
		}
	}
	return daemonCommandResult{err: fmt.Errorf("task not found")}
}

func (d *daemonCore) handleTaskUnfocus(args []string) daemonCommandResult {
	if !d.isWorkSession() {
		return daemonCommandResult{err: fmt.Errorf("unfocus is only available during a work session")}
	}
	if len(args) < 1 {
		return daemonCommandResult{err: fmt.Errorf("usage: task unfocus <number>")}
	}
	pos, err := strconv.Atoi(args[0])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid number: %s", args[0])}
	}
	if pos < 1 || pos > len(d.focused) {
		return daemonCommandResult{err: fmt.Errorf("focus position %d out of range (1-%d)", pos, len(d.focused))}
	}
	d.focused = append(d.focused[:pos-1], d.focused[pos:]...)
	return daemonCommandResult{message: "task unfocused"}
}

func (d *daemonCore) handleTaskUp(args []string) daemonCommandResult {
	if !d.isWorkSession() {
		return daemonCommandResult{err: fmt.Errorf("up is only available during a work session")}
	}
	if len(args) < 1 {
		return daemonCommandResult{err: fmt.Errorf("usage: task up <number>")}
	}
	pos, err := strconv.Atoi(args[0])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid number: %s", args[0])}
	}
	if pos < 2 || pos > len(d.focused) {
		return daemonCommandResult{err: fmt.Errorf("cannot move position %d up", pos)}
	}
	d.focused[pos-1], d.focused[pos-2] = d.focused[pos-2], d.focused[pos-1]
	return daemonCommandResult{message: "task moved up"}
}

func (d *daemonCore) handleTaskDown(args []string) daemonCommandResult {
	if !d.isWorkSession() {
		return daemonCommandResult{err: fmt.Errorf("down is only available during a work session")}
	}
	if len(args) < 1 {
		return daemonCommandResult{err: fmt.Errorf("usage: task down <number>")}
	}
	pos, err := strconv.Atoi(args[0])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid number: %s", args[0])}
	}
	if pos < 1 || pos >= len(d.focused) {
		return daemonCommandResult{err: fmt.Errorf("cannot move position %d down", pos)}
	}
	d.focused[pos-1], d.focused[pos] = d.focused[pos], d.focused[pos-1]
	return daemonCommandResult{message: "task moved down"}
}
```

Update `handleStop` to clear focus:
```go
func (d *daemonCore) handleStop(_ []string) daemonCommandResult {
	d.cycle.Stop()
	d.focused = nil
	return daemonCommandResult{message: "stopped and returned to idle"}
}
```

Update `handleTaskDone` to also remove from focused list:
```go
// After completing, remove from focused list if present
for i, f := range d.focused {
	if f.ID == id {
		d.focused = append(d.focused[:i], d.focused[i+1:]...)
		break
	}
}
```

**Step 4: Run tests**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./cmd/throwntom/`
Expected: PASS

**Step 5: Commit**

```
test: add focus state management tests
feat: add focus/unfocus/up/down commands with work session guard
```

---

### Task 10: Focus Prompt State

**Files:**
- Modify: `cmd/throwntom/daemon_core.go`
- Modify: `cmd/throwntom/daemon_core_test.go`

The focus prompt intercepts `start` and `confirm` (when transitioning to work). Instead of immediately starting, it sets a pending state. The UI renders the prompt. User input during the prompt is handled specially.

**Step 1: Write failing tests**

```go
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
}

func TestStartSkipsPromptWhenNoTasks(t *testing.T) {
	core := newTestCoreWithTasks(t)
	result := core.execute("start")
	if core.isFocusPromptPending() {
		t.Fatal("expected no prompt when no tasks")
	}
	if result.message != "pomodoro started" {
		t.Fatalf("expected immediate start, got %q", result.message)
	}
}

func TestFocusPromptSelectAndStart(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add first task")
	core.execute("task add second task")
	core.execute("start") // enters prompt
	result := core.execute("1") // select task 1
	if !strings.Contains(result.message, "Focused") {
		t.Fatalf("expected focused confirmation, got %q", result.message)
	}
	result = core.execute("") // empty enter = confirm and start
	if core.isFocusPromptPending() {
		t.Fatal("expected prompt to clear after confirm")
	}
	if core.cycle.Status() != "pomodoro" {
		t.Fatalf("expected pomodoro state, got %s", core.cycle.Status())
	}
	if len(core.focusedTasks()) != 1 {
		t.Fatalf("expected 1 focused task, got %d", len(core.focusedTasks()))
	}
}

func TestFocusPromptSkip(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add something")
	core.execute("start") // enters prompt
	core.execute("")       // skip (empty enter with no selections)
	if core.isFocusPromptPending() {
		t.Fatal("expected prompt to clear")
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
		t.Fatalf("expected add confirmation, got %q", result.message)
	}
	active := core.tasks.Active()
	if len(active) != 2 {
		t.Fatalf("expected 2 active tasks, got %d", len(active))
	}
}

func TestConfirmToWorkTriggersFocusPrompt(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add keep working")
	core.execute("start")
	core.execute("")  // skip prompt
	core.cycle.CompletePeriod() // work done
	core.execute("confirm")     // transitions to short break
	core.cycle.CompletePeriod() // break done
	core.execute("confirm")     // should trigger prompt (next is work)
	if !core.isFocusPromptPending() {
		t.Fatal("expected focus prompt when confirming into work phase")
	}
}
```

**Step 2: Run tests to verify they fail**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s -run "TestFocusPrompt|TestStartEnters|TestStartSkips|TestConfirmToWork" ./cmd/throwntom/`
Expected: FAIL — `isFocusPromptPending` undefined

**Step 3: Implement focus prompt state**

Add to `daemonCore`:
```go
type daemonCore struct {
	// ... existing fields ...
	pendingFocusPrompt  bool
	pendingFocusToggled map[int]bool // tracks toggled task IDs during prompt
}
```

Add accessor:
```go
func (d *daemonCore) isFocusPromptPending() bool {
	return d.pendingFocusPrompt
}
```

Modify `handleStart`: if tasks exist, enter prompt instead of starting.
Modify `handleConfirm`: if next state is work and tasks exist, enter prompt.
Override `execute`: if `pendingFocusPrompt`, route input to prompt handler instead of normal command dispatch.

Prompt handler logic:
- Number input → toggle that task in `pendingFocusToggled`
- `a <desc>` → add task, auto-toggle it
- Empty enter → finalize: set `d.focused` from toggled tasks, clear prompt, start pomodoro
- Return message showing current prompt state

**Step 4: Run tests**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./cmd/throwntom/`
Expected: PASS

**Step 5: Commit**

```
test: add focus prompt interaction tests
feat: implement focus prompt on start and confirm-to-work
```

---

### Task 11: Focus Display in daemonControlResponse

**Files:**
- Modify: `cmd/throwntom/control.go` (add FocusLines to response)
- Modify: `cmd/throwntom/daemon_core.go` (populate FocusLines and FocusPrompt in response)
- Modify: `cmd/throwntom/daemon_core_test.go`

**Step 1: Write failing test**

```go
func TestControlResponseIncludesFocusLines(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add important")
	core.execute("start")
	core.execute("")  // skip prompt
	core.execute("task focus 1")
	resp := core.executeControlCommand("status")
	if len(resp.FocusLines) != 1 {
		t.Fatalf("expected 1 focus line, got %d", len(resp.FocusLines))
	}
	if !strings.Contains(resp.FocusLines[0], "important") {
		t.Fatalf("expected task description in focus line, got %q", resp.FocusLines[0])
	}
}

func TestControlResponseIncludesFocusPrompt(t *testing.T) {
	core := newTestCoreWithTasks(t)
	core.execute("task add pick me")
	resp := core.executeControlCommand("start")
	if resp.FocusPrompt == "" {
		t.Fatal("expected focus prompt in response")
	}
	if !strings.Contains(resp.FocusPrompt, "pick me") {
		t.Fatalf("expected task in prompt, got %q", resp.FocusPrompt)
	}
}
```

**Step 2: Run tests to verify they fail**

Expected: FAIL — `FocusLines` field doesn't exist on `daemonControlResponse`

**Step 3: Add fields to `daemonControlResponse`**

In `control.go`:
```go
type daemonControlResponse struct {
	StatusLine     string   `json:"status_line"`
	MorningPending bool     `json:"morning_pending"`
	Message        string   `json:"message"`
	Error          string   `json:"error"`
	Exit           bool     `json:"exit"`
	FocusLines     []string `json:"focus_lines,omitempty"`
	FocusPrompt    string   `json:"focus_prompt,omitempty"`
}
```

In `executeControlCommand`, populate these:
```go
func (d *daemonCore) executeControlCommand(line string) daemonControlResponse {
	result := d.execute(line)
	statusLine, morningPending := d.snapshot()
	resp := daemonControlResponse{
		StatusLine:     statusLine,
		MorningPending: morningPending,
		Message:        result.message,
		Exit:           result.exit,
		FocusLines:     d.formatFocusLines(),
	}
	if d.pendingFocusPrompt {
		resp.FocusPrompt = d.formatFocusPrompt()
	}
	if result.err != nil {
		resp.Error = result.err.Error()
	}
	return resp
}
```

Implement `formatFocusLines()` and `formatFocusPrompt()`:
```go
func (d *daemonCore) formatFocusLines() []string {
	if len(d.focused) == 0 {
		return nil
	}
	lines := []string{"Focus:"}
	for i, tk := range d.focused {
		lines = append(lines, fmt.Sprintf("  %d. %s", i+1, tk.Description))
	}
	return lines
}

func (d *daemonCore) formatFocusPrompt() string {
	active := d.tasks.Active()
	var lines []string
	lines = append(lines, "Select tasks for this pomodoro:")
	for i, tk := range active {
		marker := " "
		if d.pendingFocusToggled[tk.ID] {
			marker = "*"
		}
		lines = append(lines, fmt.Sprintf(" %s%d) %s", marker, i+1, tk.Description))
	}
	// Show toggled summary
	var selected []string
	for i, tk := range active {
		if d.pendingFocusToggled[tk.ID] {
			selected = append(selected, fmt.Sprintf("%d", i+1))
		}
	}
	if len(selected) > 0 {
		lines = append(lines, "", fmt.Sprintf("Focused: %s", strings.Join(selected, ", ")))
	}
	lines = append(lines, "", "(numbers to toggle, a <desc> to add, enter to start)")
	return strings.Join(lines, "\n")
}
```

**Step 4: Run tests**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./cmd/throwntom/`
Expected: PASS

**Step 5: Commit**

```
test: add focus lines and prompt in control response tests
feat: include focus display and prompt in daemon response
```

---

### Task 12: Bubble Tea UI — Render Focus Lines and Prompt

**Files:**
- Modify: `cmd/throwntom/interactive_callbacks.go` (add FocusSnapshot callback)
- Modify: `cmd/throwntom/interactive_tea_model.go` (render focus lines and prompt)
- Modify: `cmd/throwntom/modes.go` (wire FocusSnapshot callback)

**Step 1: Write failing test**

Add to a new or existing test file:
```go
func TestViewShowsFocusLinesAboveStatus(t *testing.T) {
	m := interactiveTeaModel{
		statusLine: "pomodoro | 24:30 | today's pomodoros=1 | pomodoros=1/4",
		focusLines: []string{"Focus:", "  1. important task"},
		width:      120,
	}
	view := m.View()
	focusIdx := strings.Index(view, "Focus:")
	statusIdx := strings.Index(view, "status:")
	if focusIdx == -1 {
		t.Fatal("expected Focus: in view")
	}
	if statusIdx == -1 {
		t.Fatal("expected status: in view")
	}
	if focusIdx >= statusIdx {
		t.Fatal("expected focus lines above status line")
	}
}

func TestViewShowsFocusPromptWhenPending(t *testing.T) {
	m := interactiveTeaModel{
		focusPrompt: "Select tasks for this pomodoro:\n 1) do thing\n\n(numbers to toggle, a <desc> to add, enter to start)",
		width:       120,
	}
	view := m.View()
	if !strings.Contains(view, "Select tasks") {
		t.Fatal("expected focus prompt in view")
	}
}
```

**Step 2: Run test to verify it fails**

Expected: FAIL — `focusLines`, `focusPrompt` not fields on model

**Step 3: Implement**

Add fields to `interactiveTeaModel`:
```go
type interactiveTeaModel struct {
	// ... existing fields ...
	focusLines  []string
	focusPrompt string
}
```

Add callback to `interactiveCallbacks`:
```go
type interactiveCallbacks struct {
	HeaderLines    []string
	HelpLines      []string
	StatusSnapshot func() (string, bool)
	FocusSnapshot  func() ([]string, string) // returns (focusLines, focusPrompt)
	Execute        func(command string) (daemonControlResponse, error)
}
```

Update `View()` to render focus lines between header and frame, and show prompt when active:
```go
func (m interactiveTeaModel) View() string {
	if m.focusPrompt != "" {
		// During focus prompt, show only the prompt and command input
		var lines []string
		for _, line := range strings.Split(m.focusPrompt, "\n") {
			lines = append(lines, clampTerminalLine(line, m.width))
		}
		lines = append(lines, clampTerminalLine("command> "+m.prompt.input, m.width))
		return strings.Join(lines, "\n")
	}

	frame := renderFrameWithWidth(m.statusLine, m.morningPending, m.message, m.prompt.input, m.width)

	var header []string
	for _, line := range m.headerLines {
		header = append(header, clampTerminalLine(line, m.width))
	}
	// Focus lines between header and status
	for _, line := range m.focusLines {
		header = append(header, clampTerminalLine(line, m.width))
	}
	if m.showHelp {
		for _, line := range m.helpLines {
			header = append(header, clampTerminalLine(line, m.width))
		}
	} else if len(m.helpLines) > 0 {
		header = append(header, clampTerminalLine("?: help", m.width))
	}

	if len(header) == 0 {
		return frame
	}
	return strings.Join(append(header, frame), "\n")
}
```

Update tick handler and `submitCommand()` to refresh focus state from response:
```go
// In tick handler
if m.callbacks.FocusSnapshot != nil {
	m.focusLines, m.focusPrompt = m.callbacks.FocusSnapshot()
}

// In submitCommand, after execute
m.focusLines = nil
m.focusPrompt = ""
if len(resp.FocusLines) > 0 {
	m.focusLines = resp.FocusLines
}
if resp.FocusPrompt != "" {
	m.focusPrompt = resp.FocusPrompt
}
```

Wire in `modes.go`:

In `localModeCallbacks`, add:
```go
FocusSnapshot: func() ([]string, string) {
	return core.formatFocusLines(), ""
},
```

In `shellModeCallbacks`, add a FocusSnapshot that queries via socket (or uses cached response data).

**Step 4: Run tests**

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./cmd/throwntom/`
Expected: PASS

**Step 5: Commit**

```
test: add focus display rendering tests
feat: render focus lines and prompt in Bubble Tea UI
```

---

### Task 13: Full Integration Test

Run the full test suite to verify everything works together:

Run: `cd .worktrees/focused-tasks && go test -timeout 30s ./...`
Expected: ALL PASS

Run: `cd .worktrees/focused-tasks && go build ./cmd/throwntom/`
Expected: builds successfully

Run: `cd .worktrees/focused-tasks && golangci-lint run`
Expected: no new warnings

**Commit:**

```
chore: verify full test suite passes with focused tasks feature
```

---

### Task 14: File Size Check

Verify no file exceeds 500 lines. If `daemon_core.go` is too large (currently 318 + ~150 lines of task handlers), extract task handlers to a new file `cmd/throwntom/daemon_task_handlers.go`.

Run: `cd .worktrees/focused-tasks && cloc --by-file cmd/throwntom/ internal/task/`

If any file > 500 lines, refactor:
- Extract `handleTask*` methods to `daemon_task_handlers.go`
- Extract focus prompt logic to `daemon_focus_prompt.go`

**Commit (if needed):**

```
refactor: extract task handlers to separate file for size compliance
```
