package task

import (
	"path/filepath"
	"testing"
	"time"
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
	path := filepath.Join(t.TempDir(), "tasks.json")
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf("NewFileStore: %v", err)
	}

	before := time.Now()
	task, err := store.Add("implement feature")
	after := time.Now()

	if err != nil {
		t.Fatalf("Add: %v", err)
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
	path := filepath.Join(t.TempDir(), "tasks.json")
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf("NewFileStore: %v", err)
	}

	if _, err := store.Add("task one"); err != nil {
		t.Fatalf("Add: %v", err)
	}
	if _, err := store.Add("task two"); err != nil {
		t.Fatalf("Add: %v", err)
	}

	active := store.Active()
	if len(active) != 2 {
		t.Fatalf("expected 2 active tasks, got %d", len(active))
	}
	if active[0].Description != "task one" {
		t.Errorf("expected first task 'task one', got %q", active[0].Description)
	}
	if active[1].Description != "task two" {
		t.Errorf("expected second task 'task two', got %q", active[1].Description)
	}
}

func TestFileStoreIDsAutoIncrement(t *testing.T) {
	path := filepath.Join(t.TempDir(), "tasks.json")
	store, err := NewFileStore(path)
	if err != nil {
		t.Fatalf("NewFileStore: %v", err)
	}

	t1, err := store.Add("first")
	if err != nil {
		t.Fatalf("Add: %v", err)
	}
	t2, err := store.Add("second")
	if err != nil {
		t.Fatalf("Add: %v", err)
	}
	t3, err := store.Add("third")
	if err != nil {
		t.Fatalf("Add: %v", err)
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
