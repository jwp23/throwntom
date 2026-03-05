package task

import (
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
