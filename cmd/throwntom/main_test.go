package main

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
)

func TestCommandHelpIncludesAllCommands(t *testing.T) {
	help := core.Help()
	for _, cmd := range []string{"new-cycle", "pause", "resume", "skip", "stop", "status", "test-sound", "quit"} {
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

func TestConfigDirPathReturnsPathWithoutCreating(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	path, err := config.DirPath("tasks.json")
	if err != nil {
		t.Fatalf("config.DirPath: %v", err)
	}
	dir := filepath.Dir(path)
	if _, err := os.Stat(dir); err == nil {
		t.Fatalf("expected config dir NOT to exist before ensureConfigDir, but it does at %s", dir)
	}
}

func TestEnsureConfigDirCreatesDirectory(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	if err := ensureConfigDir(); err != nil {
		t.Fatalf("ensureConfigDir: %v", err)
	}
	path, err := config.DirPath("tasks.json")
	if err != nil {
		t.Fatalf("config.DirPath: %v", err)
	}
	dir := filepath.Dir(path)
	info, err := os.Stat(dir)
	if err != nil {
		t.Fatalf("expected config dir to exist at %s: %v", dir, err)
	}
	if !info.IsDir() {
		t.Fatalf("expected %s to be a directory", dir)
	}
}

// captureStdout captures os.Stdout output during fn execution.
// Not parallel-safe.
func captureStdout(t *testing.T, fn func()) string {
	t.Helper()
	old := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("create pipe: %v", err)
	}
	os.Stdout = w
	fn()
	_ = w.Close()
	os.Stdout = old
	var buf bytes.Buffer
	if _, err := io.Copy(&buf, r); err != nil {
		t.Fatalf("read pipe: %v", err)
	}
	return buf.String()
}

// captureStderr captures os.Stderr output during fn execution.
// Not parallel-safe.
func captureStderr(t *testing.T, fn func()) string {
	t.Helper()
	old := os.Stderr
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatalf("create pipe: %v", err)
	}
	os.Stderr = w
	fn()
	_ = w.Close()
	os.Stderr = old
	var buf bytes.Buffer
	if _, err := io.Copy(&buf, r); err != nil {
		t.Fatalf("read pipe: %v", err)
	}
	return buf.String()
}

func TestVersionIsSet(t *testing.T) {
	if version == "" {
		t.Fatal("expected version to be set, got empty string")
	}
}

func TestPrintUsageExcludesInteractiveCommands(t *testing.T) {
	out := captureStdout(t, printUsage)
	lower := strings.ToLower(out)
	if strings.Contains(lower, "commands:") {
		t.Fatalf("printUsage should not contain interactive commands section, got:\n%s", out)
	}
}

func TestPrintFlagUsageExcludesInteractiveCommands(t *testing.T) {
	out := captureStderr(t, printFlagUsage)
	lower := strings.ToLower(out)
	if strings.Contains(lower, "commands:") {
		t.Fatalf("printFlagUsage should not contain interactive commands section, got:\n%s", out)
	}
}

func TestPrintFlagUsageIncludesVersionOption(t *testing.T) {
	out := captureStderr(t, printFlagUsage)
	if !strings.Contains(out, "--version") {
		t.Fatalf("printFlagUsage should contain --version option, got:\n%s", out)
	}
}

func TestPrintUsageIncludesVersionFlag(t *testing.T) {
	out := captureStdout(t, printUsage)
	if !strings.Contains(out, "--version") {
		t.Fatalf("printUsage should contain --version in usage line, got:\n%s", out)
	}
}

func TestLoadConfigUsesDefaultHomeConfigFile(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	configPath := filepath.Join(home, ".config", "throwntom", "config.toml")
	if err := os.MkdirAll(filepath.Dir(configPath), 0o755); err != nil {
		t.Fatalf("mkdir default config dir: %v", err)
	}
	if err := os.WriteFile(configPath, []byte("[[schedule]]\ndays = [\"Mon\"]\ntime = \"10:30\""), 0o644); err != nil {
		t.Fatalf("write default config file: %v", err)
	}

	cfg, err := config.LoadDefault("")
	if err != nil {
		t.Fatalf("load default config: %v", err)
	}
	if len(cfg.Schedule) == 0 || cfg.Schedule[0].Time != "10:30" {
		t.Fatalf("expected schedule time from default config file, got %v", cfg.Schedule)
	}
}
