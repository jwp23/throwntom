//go:build e2e

package e2e_test

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func buildBinary(t *testing.T) string {
	t.Helper()

	tmpDir := t.TempDir()
	binName := "throwntom-e2e"
	if runtime.GOOS == "windows" {
		binName += ".exe"
	}
	binPath := filepath.Join(tmpDir, binName)
	cmd := exec.Command("go", "build", "-o", binPath, "../cmd/throwntom")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("build binary: %v\n%s", err, out)
	}
	return binPath
}

func TestUnexpectedPositionalArgExitsNonZero(t *testing.T) {
	bin := buildBinary(t)

	cmd := exec.Command(bin, "daemon", "extra")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		t.Fatal("expected non-zero exit for unexpected positional arg")
	}

	output := stderr.String()
	if !strings.Contains(output, "argument error:") {
		t.Fatalf("expected positional argument error, got %q", output)
	}
}

func TestNonInteractiveRejected(t *testing.T) {
	bin := buildBinary(t)

	cmd := exec.Command(bin)
	cmd.Stdin = strings.NewReader("")
	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		t.Fatal("expected non-zero exit when stdin/stdout are not interactive terminals")
	}
	if !strings.Contains(stderr.String(), "daemon requires an interactive terminal") {
		t.Fatalf("expected interactive terminal error, got %q", stderr.String())
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
