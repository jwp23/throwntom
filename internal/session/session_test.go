package session

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v2/internal/app"
	"github.com/jwp23/throwntom/v2/internal/engine"
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

func TestIsSameDay(t *testing.T) {
	loc := time.Local
	tests := []struct {
		name string
		a, b time.Time
		want bool
	}{
		{"same day", time.Date(2026, 3, 5, 10, 0, 0, 0, loc), time.Date(2026, 3, 5, 23, 59, 0, 0, loc), true},
		{"different day", time.Date(2026, 3, 5, 23, 59, 0, 0, loc), time.Date(2026, 3, 6, 0, 1, 0, 0, loc), false},
		{"different month", time.Date(2026, 2, 28, 12, 0, 0, 0, loc), time.Date(2026, 3, 1, 12, 0, 0, 0, loc), false},
		{"same midnight", time.Date(2026, 3, 5, 0, 0, 0, 0, loc), time.Date(2026, 3, 5, 0, 0, 0, 0, loc), true},
	}
	for _, tc := range tests {
		if got := IsSameDay(tc.a, tc.b); got != tc.want {
			t.Errorf("%s: IsSameDay(%v, %v) = %v, want %v", tc.name, tc.a, tc.b, got, tc.want)
		}
	}
}
