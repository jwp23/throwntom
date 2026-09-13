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

func TestResolvePathKeepsAnExplicitPath(t *testing.T) {
	got, err := ResolvePath("/explicit/config.toml")
	if err != nil {
		t.Fatal(err)
	}
	if got != "/explicit/config.toml" {
		t.Fatalf("ResolvePath = %q, want the explicit path unchanged", got)
	}
}

func TestResolvePathFallsBackToDirPathWhenEmpty(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	got, err := ResolvePath("")
	if err != nil {
		t.Fatal(err)
	}
	want, err := DirPath("config.toml")
	if err != nil {
		t.Fatal(err)
	}
	if got != want {
		t.Fatalf("ResolvePath(\"\") = %q, want %q", got, want)
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
