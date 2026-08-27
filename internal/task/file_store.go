package task

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/jwp23/throwntom/v3/internal/atomicfile"
)

type Task struct {
	ID          int       `json:"id"`
	Description string    `json:"description"`
	Done        bool      `json:"done"`
	CreatedAt   time.Time `json:"created_at"`
	CompletedAt time.Time `json:"completed_at"`
}

type fileData struct {
	NextID int    `json:"next_id"`
	Tasks  []Task `json:"tasks"`
}

// FileStore persists tasks to a JSON file on disk.
type FileStore struct {
	path string
	data fileData
}

// NewFileStore creates or loads a FileStore from the given file path.
func NewFileStore(path string) (*FileStore, error) {
	fs := &FileStore{
		path: path,
		data: fileData{NextID: 1},
	}
	if err := fs.load(); err != nil {
		return nil, err
	}
	return fs, nil
}

// Add creates a new task with the given description and persists it.
func (fs *FileStore) Add(description string) (Task, error) {
	t := Task{
		ID:          fs.data.NextID,
		Description: description,
		CreatedAt:   time.Now(),
	}
	fs.data.NextID++
	fs.data.Tasks = append(fs.data.Tasks, t)
	if err := fs.save(); err != nil {
		return Task{}, fmt.Errorf("saving after add: %w", err)
	}
	return t, nil
}

// Complete marks a task as done by ID.
func (fs *FileStore) Complete(id int) error {
	for i := range fs.data.Tasks {
		if fs.data.Tasks[i].ID == id {
			if fs.data.Tasks[i].Done {
				return fmt.Errorf("task %d is already completed", id)
			}
			fs.data.Tasks[i].Done = true
			fs.data.Tasks[i].CompletedAt = time.Now()
			return fs.save()
		}
	}
	return fmt.Errorf("task %d not found", id)
}

// Remove deletes a task by ID.
func (fs *FileStore) Remove(id int) error {
	for i, t := range fs.data.Tasks {
		if t.ID == id {
			fs.data.Tasks = append(fs.data.Tasks[:i], fs.data.Tasks[i+1:]...)
			return fs.save()
		}
	}
	return fmt.Errorf("task %d not found", id)
}

// Active returns all tasks that are not done.
func (fs *FileStore) Active() []Task {
	var result []Task
	for _, t := range fs.data.Tasks {
		if !t.Done {
			result = append(result, t)
		}
	}
	return result
}

// Completed returns all tasks that are done.
func (fs *FileStore) Completed() []Task {
	var result []Task
	for _, t := range fs.data.Tasks {
		if t.Done {
			result = append(result, t)
		}
	}
	return result
}

// ClearCompleted removes all completed tasks.
func (fs *FileStore) ClearCompleted() error {
	var kept []Task
	for _, t := range fs.data.Tasks {
		if !t.Done {
			kept = append(kept, t)
		}
	}
	fs.data.Tasks = kept
	return fs.save()
}

// ActiveTaskID maps a 1-based position in the active task list to a task ID.
func (fs *FileStore) ActiveTaskID(position int) (int, error) {
	active := fs.Active()
	if position < 1 || position > len(active) {
		return 0, fmt.Errorf("position %d out of range (1-%d)", position, len(active))
	}
	return active[position-1].ID, nil
}

func (fs *FileStore) load() error {
	raw, err := os.ReadFile(fs.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return fmt.Errorf("reading task file: %w", err)
	}
	if err := json.Unmarshal(raw, &fs.data); err != nil {
		return fmt.Errorf("parsing task file: %w", err)
	}
	return nil
}

// save writes the task file atomically: readers either see the previous file
// or the new one, never a half-written one.
func (fs *FileStore) save() error {
	raw, err := json.MarshalIndent(fs.data, "", "  ")
	if err != nil {
		return fmt.Errorf("marshaling task data: %w", err)
	}
	if err := atomicfile.Write(fs.path, raw, 0o644); err != nil {
		return fmt.Errorf("writing task file: %w", err)
	}
	return nil
}
