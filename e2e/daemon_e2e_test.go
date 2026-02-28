//go:build e2e

package e2e_test

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

func buildBinary(t *testing.T) string {
	t.Helper()

	tmpDir := t.TempDir()
	binName := "urgtomat-e2e"
	if runtime.GOOS == "windows" {
		binName += ".exe"
	}
	binPath := filepath.Join(tmpDir, binName)
	cmd := exec.Command("go", "build", "-o", binPath, "../cmd/urgtomat")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("build binary: %v\n%s", err, out)
	}
	return binPath
}

func TestUnsupportedCommandExitsNonZero(t *testing.T) {
	bin := buildBinary(t)

	cmd := exec.Command(bin, "invalid")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		t.Fatal("expected non-zero exit for unsupported command")
	}

	output := stderr.String()
	if !strings.Contains(output, "unsupported command") {
		t.Fatalf("expected unsupported command message, got %q", output)
	}
}

func TestDaemonStartsAndQuits(t *testing.T) {
	bin := buildBinary(t)

	cmd := exec.Command(bin)
	cmd.Stdin = strings.NewReader("quit\n")
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	errCh := make(chan error, 1)
	go func() {
		errCh <- cmd.Run()
	}()

	select {
	case err := <-errCh:
		if err != nil {
			t.Fatalf("daemon run failed: %v\nstderr=%s", err, stderr.String())
		}
	case <-time.After(5 * time.Second):
		_ = cmd.Process.Kill()
		t.Fatal("daemon did not exit after quit command")
	}

	out := stdout.String()
	if !strings.Contains(out, "urgtomat daemon started") {
		t.Fatalf("expected daemon startup output, got %q", out)
	}
	if !strings.Contains(out, "bye") {
		t.Fatalf("expected graceful quit output, got %q", out)
	}
}

func TestMissingConfigFileFails(t *testing.T) {
	bin := buildBinary(t)
	missingPath := filepath.Join(t.TempDir(), "missing.toml")

	cmd := exec.Command(bin, "--config", missingPath)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		t.Fatal("expected non-zero exit for missing config file")
	}
	if exitErr, ok := err.(*exec.ExitError); ok {
		if exitErr.ExitCode() == 0 {
			t.Fatal("expected non-zero exit code")
		}
	}

	output := stderr.String()
	if !strings.Contains(output, "config error:") {
		t.Fatalf("expected config error output, got %q", output)
	}
	if !strings.Contains(output, missingPath) {
		t.Fatalf("expected missing path in error output, got %q", output)
	}
}

func TestUnexpectedPositionalArgExitsNonZero(t *testing.T) {
	bin := buildBinary(t)

	cmd := exec.Command(bin, "daemon")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		t.Fatal("expected non-zero exit for unexpected positional arg")
	}

	output := stderr.String()
	if !strings.Contains(output, "unexpected positional arguments") {
		t.Fatalf("expected positional argument error, got %q", output)
	}
}
