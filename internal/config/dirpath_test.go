package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDirPathJoinsConfigDir(t *testing.T) {
	home, err := os.UserHomeDir()
	if err != nil {
		t.Fatal(err)
	}
	got, err := DirPath("tasks.json")
	if err != nil {
		t.Fatal(err)
	}
	want := filepath.Join(home, ".config", "throwntom", "tasks.json")
	if got != want {
		t.Fatalf("DirPath = %q, want %q", got, want)
	}
}
