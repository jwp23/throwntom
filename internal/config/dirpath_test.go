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

func TestLoadDefaultUsesExplicitPath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "c.toml")
	if err := os.WriteFile(path, []byte("repeat_secs = 7\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg, err := LoadDefault(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.RepeatSecs != 7 {
		t.Fatalf("RepeatSecs = %d", cfg.RepeatSecs)
	}
}

func TestLoadDefaultReturnsDefaultWhenMissing(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	cfg, err := LoadDefault("")
	if err != nil {
		t.Fatal(err)
	}
	if cfg.RepeatSecs != Default().RepeatSecs {
		t.Fatalf("RepeatSecs = %d, want default %d", cfg.RepeatSecs, Default().RepeatSecs)
	}
}
