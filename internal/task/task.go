package task

import "time"

// Task represents a single focused task associated with a pomodoro session.
type Task struct {
	ID          int       `json:"id"`
	Description string    `json:"description"`
	Done        bool      `json:"done"`
	CreatedAt   time.Time `json:"created_at"`
	CompletedAt time.Time `json:"completed_at"`
}

// Store defines the operations for managing focused tasks.
type Store interface {
	Add(description string) (Task, error)
	Complete(id int) error
	Remove(id int) error
	Active() []Task
	Completed() []Task
	ClearCompleted() error
}
