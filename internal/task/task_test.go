package task

import (
	"path/filepath"
	"testing"
	"time"
)

const (
	testTasksFile   = "tasks.json"
	fmtNewFileStore = "NewFileStore: %v"
	fmtAdd          = "Add: %v"
	fmtComplete     = "Complete: %v"
	testTaskOne     = "task one"
	testTaskTwo     = "task two"
)

func TestTaskStructFields(t *testing.T) {
	now := time.Now()
	task := Task{
		ID:          1,
		Description: "write tests",
		Done:        false,
		CreatedAt:   now,
		CompletedAt: time.Time{},
	}

	if task.ID != 1 {
		t.Errorf("expected ID 1, got %d", task.ID)
	}
	if task.Description != "write tests" {
		t.Errorf("expected Description 'write tests', got %q", task.Description)
	}
	if task.Done {
		t.Error("expected Done to be false")
	}
	if !task.CreatedAt.Equal(now) {
		t.Errorf("expected CreatedAt %v, got %v", now, task.CreatedAt)
	}
	if !task.CompletedAt.IsZero() {
		t.Errorf("expected CompletedAt to be zero, got %v", task.CompletedAt)
	}
}

func TestFileStoreAddCreatesTask(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	before := time.Now()
	task, err := store.Add("implement feature")
	after := time.Now()

	if err != nil {
		t.Fatalf(fmtAdd, err)
	}
	if task.ID != 1 {
		t.Errorf("expected ID 1, got %d", task.ID)
	}
	if task.Description != "implement feature" {
		t.Errorf("expected Description 'implement feature', got %q", task.Description)
	}
	if task.Done {
		t.Error("expected Done to be false")
	}
	if task.CreatedAt.Before(before) || task.CreatedAt.After(after) {
		t.Errorf("CreatedAt %v not between %v and %v", task.CreatedAt, before, after)
	}
	if !task.CompletedAt.IsZero() {
		t.Errorf("expected CompletedAt to be zero, got %v", task.CompletedAt)
	}
}

func TestFileStoreActiveReturnsUncompleted(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	if _, err := store.Add(testTaskOne); err != nil {
		t.Fatalf(fmtAdd, err)
	}
	if _, err := store.Add(testTaskTwo); err != nil {
		t.Fatalf(fmtAdd, err)
	}

	active := store.Active()
	if len(active) != 2 {
		t.Fatalf("expected 2 active tasks, got %d", len(active))
	}
	if active[0].Description != testTaskOne {
		t.Errorf("expected first task 'task one', got %q", active[0].Description)
	}
	if active[1].Description != testTaskTwo {
		t.Errorf("expected second task 'task two', got %q", active[1].Description)
	}
}

func TestFileStoreIDsAutoIncrement(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	t1, err := store.Add("first")
	if err != nil {
		t.Fatalf(fmtAdd, err)
	}
	t2, err := store.Add("second")
	if err != nil {
		t.Fatalf(fmtAdd, err)
	}
	t3, err := store.Add("third")
	if err != nil {
		t.Fatalf(fmtAdd, err)
	}

	if t1.ID != 1 {
		t.Errorf("expected first ID 1, got %d", t1.ID)
	}
	if t2.ID != 2 {
		t.Errorf("expected second ID 2, got %d", t2.ID)
	}
	if t3.ID != 3 {
		t.Errorf("expected third ID 3, got %d", t3.ID)
	}
}

func TestFileStoreCompleteMarksTaskDone(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	if _, err := store.Add("task to complete"); err != nil {
		t.Fatalf(fmtAdd, err)
	}

	before := time.Now()
	if err := store.Complete(1); err != nil {
		t.Fatalf(fmtComplete, err)
	}
	after := time.Now()

	active := store.Active()
	if len(active) != 0 {
		t.Errorf("expected 0 active tasks, got %d", len(active))
	}

	completed := store.Completed()
	if len(completed) != 1 {
		t.Fatalf("expected 1 completed task, got %d", len(completed))
	}
	if !completed[0].Done {
		t.Error("expected Done to be true")
	}
	if completed[0].CompletedAt.Before(before) || completed[0].CompletedAt.After(after) {
		t.Errorf("CompletedAt %v not between %v and %v", completed[0].CompletedAt, before, after)
	}
}

func TestFileStoreCompleteUnknownIDReturnsError(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	if err := store.Complete(99); err == nil {
		t.Error("expected error for unknown ID, got nil")
	}
}

func TestFileStoreCompleteAlreadyDoneReturnsError(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	if _, err := store.Add("task"); err != nil {
		t.Fatalf(fmtAdd, err)
	}
	if err := store.Complete(1); err != nil {
		t.Fatalf(fmtComplete, err)
	}
	if err := store.Complete(1); err == nil {
		t.Error("expected error for already-done task, got nil")
	}
}

func TestFileStoreRemoveDeletesTask(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	if _, err := store.Add("keep"); err != nil {
		t.Fatalf(fmtAdd, err)
	}
	if _, err := store.Add("remove me"); err != nil {
		t.Fatalf(fmtAdd, err)
	}

	if err := store.Remove(2); err != nil {
		t.Fatalf("Remove: %v", err)
	}

	active := store.Active()
	if len(active) != 1 {
		t.Fatalf("expected 1 active task, got %d", len(active))
	}
	if active[0].Description != "keep" {
		t.Errorf("expected remaining task 'keep', got %q", active[0].Description)
	}
}

func TestFileStoreRemoveUnknownIDReturnsError(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	if err := store.Remove(99); err == nil {
		t.Error("expected error for unknown ID, got nil")
	}
}

func TestFileStoreClearCompletedRemovesDoneTasks(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	if _, err := store.Add("active task"); err != nil {
		t.Fatalf(fmtAdd, err)
	}
	if _, err := store.Add("done task"); err != nil {
		t.Fatalf(fmtAdd, err)
	}
	if err := store.Complete(2); err != nil {
		t.Fatalf(fmtComplete, err)
	}

	if err := store.ClearCompleted(); err != nil {
		t.Fatalf("ClearCompleted: %v", err)
	}

	active := store.Active()
	if len(active) != 1 {
		t.Fatalf("expected 1 active task, got %d", len(active))
	}
	completed := store.Completed()
	if len(completed) != 0 {
		t.Errorf("expected 0 completed tasks, got %d", len(completed))
	}
}

func TestFileStorePersistsAcrossLoads(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	if _, err := store.Add(testTaskOne); err != nil {
		t.Fatalf(fmtAdd, err)
	}
	if _, err := store.Add(testTaskTwo); err != nil {
		t.Fatalf(fmtAdd, err)
	}
	if err := store.Complete(1); err != nil {
		t.Fatalf(fmtComplete, err)
	}

	reloaded, err := NewFileStore(path)
	if err != nil {
		t.Fatalf("NewFileStore reload: %v", err)
	}

	active := reloaded.Active()
	if len(active) != 1 {
		t.Fatalf("expected 1 active task after reload, got %d", len(active))
	}
	if active[0].Description != testTaskTwo {
		t.Errorf("expected active task 'task two', got %q", active[0].Description)
	}

	completed := reloaded.Completed()
	if len(completed) != 1 {
		t.Fatalf("expected 1 completed task after reload, got %d", len(completed))
	}
	if completed[0].Description != testTaskOne {
		t.Errorf("expected completed task 'task one', got %q", completed[0].Description)
	}
}

func TestFileStoreNextIDSurvivesReload(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	t1, err := store.Add("first")
	if err != nil {
		t.Fatalf(fmtAdd, err)
	}
	if t1.ID != 1 {
		t.Errorf("expected first task ID 1, got %d", t1.ID)
	}

	reloaded, err := NewFileStore(path)
	if err != nil {
		t.Fatalf("NewFileStore reload: %v", err)
	}

	t2, err := reloaded.Add("second")
	if err != nil {
		t.Fatalf("Add after reload: %v", err)
	}
	if t2.ID != 2 {
		t.Errorf("expected second task ID 2, got %d", t2.ID)
	}
}

func TestFileStoreActiveTaskID(t *testing.T) {
	path := filepath.Join(t.TempDir(), testTasksFile)
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf(fmtNewFileStore, err)
	}

	// Add 3 tasks: IDs 1, 2, 3
	if _, err := store.Add("first"); err != nil {
		t.Fatalf(fmtAdd, err)
	}
	if _, err := store.Add("second"); err != nil {
		t.Fatalf(fmtAdd, err)
	}
	if _, err := store.Add("third"); err != nil {
		t.Fatalf(fmtAdd, err)
	}

	// Complete the middle one (ID=2), so active list is [ID=1, ID=3]
	if err := store.Complete(2); err != nil {
		t.Fatalf(fmtComplete, err)
	}

	// Position 1 should map to ID 1
	id, err := store.ActiveTaskID(1)
	if err != nil {
		t.Fatalf("ActiveTaskID(1): %v", err)
	}
	if id != 1 {
		t.Errorf("expected position 1 -> ID 1, got %d", id)
	}

	// Position 2 should map to ID 3
	id, err = store.ActiveTaskID(2)
	if err != nil {
		t.Fatalf("ActiveTaskID(2): %v", err)
	}
	if id != 3 {
		t.Errorf("expected position 2 -> ID 3, got %d", id)
	}

	// Position 3 should error (only 2 active tasks)
	_, err = store.ActiveTaskID(3)
	if err == nil {
		t.Error("expected error for out-of-range position 3, got nil")
	}

	// Position 0 should error (1-based)
	_, err = store.ActiveTaskID(0)
	if err == nil {
		t.Error("expected error for position 0, got nil")
	}
}
