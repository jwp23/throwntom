package eventlog

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestWriterAppendsJSONL(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	w := NewWriter(path)

	if err := w.Log("pomodoro_started", nil); err != nil {
		t.Fatalf("Log: %v", err)
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
	if len(lines) != 1 {
		t.Fatalf("expected 1 line, got %d", len(lines))
	}
	var ev Event
	if err := json.Unmarshal([]byte(lines[0]), &ev); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if ev.Type != "pomodoro_started" {
		t.Fatalf("expected type pomodoro_started, got %s", ev.Type)
	}
	if ev.Timestamp.IsZero() {
		t.Fatal("expected non-zero timestamp")
	}
}

func TestWriterMultipleEvents(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	w := NewWriter(path)

	for _, typ := range []string{"pomodoro_started", "pomodoro_completed", "break_started"} {
		if err := w.Log(typ, nil); err != nil {
			t.Fatalf("Log(%s): %v", typ, err)
		}
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 lines, got %d", len(lines))
	}
}

func TestWriterWithData(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	w := NewWriter(path)

	data := map[string]any{"kind": "short"}
	if err := w.Log("break_started", data); err != nil {
		t.Fatalf("Log: %v", err)
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	var ev Event
	if err := json.Unmarshal([]byte(strings.TrimSpace(string(raw))), &ev); err != nil {
		t.Fatalf("Unmarshal: %v", err)
	}
	if ev.Data["kind"] != "short" {
		t.Fatalf("expected data.kind=short, got %v", ev.Data["kind"])
	}
}

func TestWriterCreatesFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "subdir", "events.jsonl")
	w := NewWriter(path)

	if err := w.Log("pomodoro_started", nil); err != nil {
		t.Fatalf("Log: %v", err)
	}

	if _, err := os.Stat(path); os.IsNotExist(err) {
		t.Fatal("expected file to be created")
	}
}

func TestWriterConcurrentSafe(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	w := NewWriter(path)

	var wg sync.WaitGroup
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_ = w.Log("pomodoro_started", nil)
		}()
	}
	wg.Wait()

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(raw)), "\n")
	if len(lines) != 20 {
		t.Fatalf("expected 20 lines, got %d", len(lines))
	}
	for i, line := range lines {
		var ev Event
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			t.Fatalf("line %d: Unmarshal: %v", i, err)
		}
	}
}

// Suppress unused import warnings for time package used in Event struct.
var _ = time.Now
