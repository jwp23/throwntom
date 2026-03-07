package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCommandHelpIncludesAllCommands(t *testing.T) {
	help := commandsHelp()
	for _, cmd := range []string{"new-cycle", "pause", "resume", "stop", "status", "test-sound", "quit"} {
		if !strings.Contains(help, cmd) {
			t.Fatalf("expected %q in command help: %s", cmd, help)
		}
	}
	for _, removed := range []string{"help"} {
		if strings.Contains(help, removed) {
			t.Fatalf("did not expect %q in command help: %s", removed, help)
		}
	}
}

func TestRequiresInteractiveTTY(t *testing.T) {
	if err := requireInteractiveTTY(true, true); err != nil {
		t.Fatalf("expected tty precondition to pass: %v", err)
	}
	if err := requireInteractiveTTY(false, true); err == nil {
		t.Fatal("expected stdin non-tty to fail precondition")
	}
	if err := requireInteractiveTTY(true, false); err == nil {
		t.Fatal("expected stdout non-tty to fail precondition")
	}
}

func TestLoadConfigUsesDefaultHomeConfigFile(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	configPath := filepath.Join(home, ".config", "throwntom", "config.toml")
	if err := os.MkdirAll(filepath.Dir(configPath), 0o755); err != nil {
		t.Fatalf("mkdir default config dir: %v", err)
	}
	if err := os.WriteFile(configPath, []byte("[schedule]\ntime = \"10:30\""), 0o644); err != nil {
		t.Fatalf("write default config file: %v", err)
	}

	cfg, err := loadConfig("")
	if err != nil {
		t.Fatalf("load default config: %v", err)
	}
	if cfg.Schedule.Time != "10:30" {
		t.Fatalf("expected schedule time from default config file, got %q", cfg.Schedule.Time)
	}
}
