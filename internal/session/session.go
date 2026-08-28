package session

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/jwp23/throwntom/v3/internal/atomicfile"
	"github.com/jwp23/throwntom/v3/internal/pomodoro"
)

type Data struct {
	SavedAt        time.Time         `json:"saved_at"`
	Timer          pomodoro.Snapshot `json:"timer"`
	FocusedTaskIDs []int             `json:"focused_task_ids"`
}

// sessionFileMode keeps the session readable only by its owner: the session
// records how the user spends their day, so owner-only is a choice, not an
// accident of the temp-file API's default mode.
const sessionFileMode = 0o600

// Save writes the session atomically: readers either see the previous file or
// the new one, never a half-written one. The core saves from a background
// goroutine, so a reader can hit any moment of a save.
func Save(path string, d Data) error {
	raw, err := json.MarshalIndent(d, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal session: %w", err)
	}
	if err := atomicfile.Write(path, raw, sessionFileMode); err != nil {
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
