package session

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/app"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

func TestSaveLoadRoundTrip(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "session.json")

	want := Data{
		SavedAt: time.Now().Truncate(time.Second),
		App: app.Snapshot{
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
	if got.App.Engine.State != want.App.Engine.State {
		t.Errorf("State: got %v, want %v", got.App.Engine.State, want.App.Engine.State)
	}
	if got.App.Engine.CompletedToday != want.App.Engine.CompletedToday {
		t.Errorf("CompletedToday: got %d, want %d", got.App.Engine.CompletedToday, want.App.Engine.CompletedToday)
	}
	if !got.App.PhaseEndAt.Equal(want.App.PhaseEndAt) {
		t.Errorf("PhaseEndAt: got %v, want %v", got.App.PhaseEndAt, want.App.PhaseEndAt)
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
