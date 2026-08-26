package session

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/jwp23/throwntom/v3/internal/app"
)

type Data struct {
	SavedAt        time.Time    `json:"saved_at"`
	App            app.Snapshot `json:"app"`
	FocusedTaskIDs []int        `json:"focused_task_ids"`
}

// Save writes the session atomically: readers either see the previous file or
// the new one, never a half-written one. The core saves from a background
// goroutine, so a reader can hit any moment of a save.
func Save(path string, d Data) error {
	raw, err := json.MarshalIndent(d, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal session: %w", err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), filepath.Base(path)+".tmp*")
	if err != nil {
		return fmt.Errorf("create session temp file: %w", err)
	}
	tmpName := tmp.Name()
	defer func() { _ = os.Remove(tmpName) }()
	if _, err := tmp.Write(raw); err != nil {
		_ = tmp.Close()
		return fmt.Errorf("write session: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("write session: %w", err)
	}
	if err := os.Rename(tmpName, path); err != nil {
		return fmt.Errorf("replace session: %w", err)
	}
	return nil
}

func Load(path string) (Data, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return Data{}, nil
		}
		return Data{}, fmt.Errorf("read session: %w", err)
	}
	var d Data
	if err := json.Unmarshal(raw, &d); err != nil {
		return Data{}, fmt.Errorf("parse session: %w", err)
	}
	return d, nil
}
