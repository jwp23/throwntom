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

func mustLog(t *testing.T, w *Writer, eventType string, data map[string]any) {
	t.Helper()
	if err := w.Log(eventType, data); err != nil {
		t.Fatalf("Log(%s): %v", eventType, err)
	}
}

func TestReadAllReturnsAll(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	w := NewWriter(path)
	mustLog(t, w, "pomodoro_started", nil)
	mustLog(t, w, "pomodoro_completed", nil)
	mustLog(t, w, "break_started", map[string]any{"kind": "short"})

	events, err := ReadAll(path)
	if err != nil {
		t.Fatalf("ReadAll: %v", err)
	}
	if len(events) != 3 {
		t.Fatalf("expected 3 events, got %d", len(events))
	}
	if events[0].Type != "pomodoro_started" {
		t.Fatalf("expected first event type pomodoro_started, got %s", events[0].Type)
	}
	if events[2].Data["kind"] != "short" {
		t.Fatalf("expected third event data.kind=short, got %v", events[2].Data["kind"])
	}
}

func TestReadAllEmpty(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	if err := os.WriteFile(path, []byte{}, 0o644); err != nil {
		t.Fatal(err)
	}
	events, err := ReadAll(path)
	if err != nil {
		t.Fatalf("ReadAll: %v", err)
	}
	if len(events) != 0 {
		t.Fatalf("expected 0 events, got %d", len(events))
	}
}

func TestReadAllMissing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nonexistent.jsonl")
	events, err := ReadAll(path)
	if err != nil {
		t.Fatalf("ReadAll: %v", err)
	}
	if len(events) != 0 {
		t.Fatalf("expected 0 events for missing file, got %d", len(events))
	}
}

func TestReadRangeFilters(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	base := time.Date(2026, 3, 15, 10, 0, 0, 0, time.Local)

	for i := 0; i < 5; i++ {
		ev := Event{
			Type:      "pomodoro_completed",
			Timestamp: base.Add(time.Duration(i) * time.Hour),
		}
		line, err := json.Marshal(ev)
		if err != nil {
			t.Fatalf("Marshal: %v", err)
		}
		line = append(line, '\n')
		if err := os.WriteFile(path, append(readFileOrEmpty(path), line...), 0o644); err != nil {
			t.Fatalf("WriteFile: %v", err)
		}
	}

	from := base.Add(1 * time.Hour)
	to := base.Add(3 * time.Hour)
	events, err := ReadRange(path, from, to)
	if err != nil {
		t.Fatalf("ReadRange: %v", err)
	}
	if len(events) != 2 {
		t.Fatalf("expected 2 events in range, got %d", len(events))
	}
}

func TestReadAllSkipsCorrupt(t *testing.T) {
	path := filepath.Join(t.TempDir(), "events.jsonl")
	w := NewWriter(path)
	mustLog(t, w, "pomodoro_started", nil)

	f, err := os.OpenFile(path, os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		t.Fatalf("OpenFile: %v", err)
	}
	if _, err := f.WriteString("not valid json\n"); err != nil {
		t.Fatalf("WriteString: %v", err)
	}
	if err := f.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	mustLog(t, w, "pomodoro_completed", nil)

	events, err := ReadAll(path)
	if err != nil {
		t.Fatalf("ReadAll: %v", err)
	}
	if len(events) != 2 {
		t.Fatalf("expected 2 events (corrupt skipped), got %d", len(events))
	}
}

func readFileOrEmpty(path string) []byte {
	data, _ := os.ReadFile(path)
	return data
}
