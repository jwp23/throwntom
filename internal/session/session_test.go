package session

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/pomodoro"
)

func TestSessionKeyIsTimer(t *testing.T) {
	raw, err := json.Marshal(Data{})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), `"timer":`) {
		t.Fatalf("expected session document to carry a \"timer\" key, got %s", raw)
	}
}

func TestSaveLoadRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "session.json")

	want := Data{
		SavedAt: time.Now().Truncate(time.Second),
		Timer: pomodoro.Snapshot{
			Engine: engine.Snapshot{
				State:          engine.Work,
				LastPhase:      engine.Work,
				CompletedToday: 3,
				WorkDayStarted: true,
			},
			PhaseEndAt: time.Now().Add(10 * time.Minute).Truncate(time.Second),
		},
		FocusedTaskIDs: []int{3, 7},
	}

	if err := Save(path, want); err != nil {
		t.Fatalf("Save: %v", err)
	}

	got, err := Load(path)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}

	if !got.SavedAt.Equal(want.SavedAt) {
		t.Errorf("SavedAt: got %v, want %v", got.SavedAt, want.SavedAt)
	}
	if got.Timer.Engine.State != want.Timer.Engine.State {
		t.Errorf("State: got %v, want %v", got.Timer.Engine.State, want.Timer.Engine.State)
	}
	if got.Timer.Engine.CompletedToday != want.Timer.Engine.CompletedToday {
		t.Errorf("CompletedToday: got %d, want %d", got.Timer.Engine.CompletedToday, want.Timer.Engine.CompletedToday)
	}
	if !got.Timer.PhaseEndAt.Equal(want.Timer.PhaseEndAt) {
		t.Errorf("PhaseEndAt: got %v, want %v", got.Timer.PhaseEndAt, want.Timer.PhaseEndAt)
	}
	if len(got.FocusedTaskIDs) != 2 || got.FocusedTaskIDs[0] != 3 || got.FocusedTaskIDs[1] != 7 {
		t.Errorf("FocusedTaskIDs: got %v, want [3 7]", got.FocusedTaskIDs)
	}
}

func TestLoadMissingFileReturnsZero(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "nonexistent.json")

	got, err := Load(path)
	if err != nil {
		t.Fatalf("Load missing file: %v", err)
	}
	if !got.SavedAt.IsZero() {
		t.Errorf("expected zero SavedAt for missing file, got %v", got.SavedAt)
	}
}

func TestLoadCorruptFileReturnsError(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "session.json")
	if err := os.WriteFile(path, []byte("{invalid"), 0o644); err != nil {
		t.Fatal(err)
	}
	_, err := Load(path)
	if err == nil {
		t.Fatal("expected error for corrupt file")
	}
}

func TestSaveKeepsSessionOwnerOnly(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "session.json")
	if err := os.WriteFile(path, []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}

	if err := Save(path, Data{SavedAt: time.Now()}); err != nil {
		t.Fatalf("Save: %v", err)
	}

	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != sessionFileMode {
		t.Fatalf("session mode: got %o, want %o", got, sessionFileMode)
	}
}

func TestSaveIsAtomicForConcurrentReaders(t *testing.T) {
	path := filepath.Join(t.TempDir(), "session.json")
	d := Data{SavedAt: time.Now(), FocusedTaskIDs: []int{1, 2, 3}}
	if err := Save(path, d); err != nil {
		t.Fatalf("seed save: %v", err)
	}

	stop := make(chan struct{})
	saveErr := make(chan error, 1)
	done := make(chan struct{})
	go func() {
		defer close(done)
		for {
			select {
			case <-stop:
				return
			default:
			}
			d.SavedAt = time.Now()
			if err := Save(path, d); err != nil {
				saveErr <- err
				return
			}
		}
	}()
	defer func() {
		close(stop)
		<-done
		select {
		case err := <-saveErr:
			t.Errorf("save: %v", err)
		default:
		}
	}()

	for i := 0; i < 200; i++ {
		loaded, err := Load(path)
		if err != nil {
			t.Fatalf("load during concurrent save: %v", err)
		}
		if loaded.SavedAt.IsZero() {
			t.Fatal("loaded a session with no saved_at while a save was in flight")
		}
	}
}
