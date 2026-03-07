package session

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/jwp23/throwntom/v2/internal/app"
)

type Data struct {
	SavedAt        time.Time    `json:"saved_at"`
	App            app.Snapshot `json:"app"`
	FocusedTaskIDs []int        `json:"focused_task_ids"`
}

func Save(path string, d Data) error {
	raw, err := json.MarshalIndent(d, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal session: %w", err)
	}
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		return fmt.Errorf("write session: %w", err)
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
