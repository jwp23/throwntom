//go:build e2e

package e2e_test

import (
	"bytes"
	"context"
	"fmt"
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

func TestScriptCommandInvocationLinuxUsesDashC(t *testing.T) {
	args := scriptCommandInvocation("linux", "echo hi", "/tmp/fake-bin")
	got := strings.Join(args, " ")
	if !strings.Contains(got, " -c ") {
		t.Fatalf("expected linux invocation to include -c form, got %q", got)
	}
	if !strings.Contains(got, "/dev/null") {
		t.Fatalf("expected linux invocation to include output file path, got %q", got)
	}
}

func TestScriptCommandInvocationDarwinUsesBsdPositionalCommand(t *testing.T) {
	args := scriptCommandInvocation("darwin", "echo hi", "/tmp/fake-bin")
	if len(args) < 7 {
		t.Fatalf("expected bsd invocation args, got %v", args)
	}
	if args[1] == "-c" {
		t.Fatalf("did not expect script -c option for darwin invocation, got %v", args)
	}
	if args[2] != "sh" || args[3] != "-c" {
		t.Fatalf("expected positional sh -c command after script output file, got %v", args)
	}
}

func TestUnexpectedPositionalArgExitsNonZero(t *testing.T) {
	bin := buildBinary(t)

	cmd := exec.Command(bin, "bogus")
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
	if !strings.Contains(stderr.String(), "throwntom requires an interactive terminal") {
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

func TestInteractiveResizeSmokeNoLineClobber(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("script-based tty smoke test is not supported on windows")
	}
	if _, err := exec.LookPath("script"); err != nil {
		t.Skip("script command not available")
	}

	bin := buildBinary(t)
	scriptCmd := `(sleep 0.25; stty cols 40 >/dev/null 2>&1 || true; sleep 0.25; stty cols 120 >/dev/null 2>&1 || true) &
exec "$1"`

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	args := scriptCommandInvocation(runtime.GOOS, scriptCmd, bin)
	cmd := exec.CommandContext(ctx, "script", args...)
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out
	stdin, err := cmd.StdinPipe()
	if err != nil {
		t.Fatalf("stdin pipe: %v", err)
	}

	if err := cmd.Start(); err != nil {
		t.Fatalf("start script command: %v", err)
	}

	go func() {
		time.Sleep(800 * time.Millisecond)
		_, _ = stdin.Write([]byte{0x03})
		_ = stdin.Close()
	}()

	err = cmd.Wait()
	if err != nil {
		t.Fatalf("interactive resize smoke failed: %v\n%s", err, out.String())
	}

	output := out.String()
	if strings.Contains(output, "\x1b[3F\x1b[J") {
		t.Fatalf("expected no legacy cursor reanchor sequence, got %q", output)
	}
	if !strings.Contains(output, "> ") {
		t.Fatalf("expected prompt in interactive output, got %q", output)
	}
	if !strings.Contains(output, "Idle") {
		t.Fatalf("expected status line in interactive output, got %q", output)
	}
	if !strings.Contains(output, "throwntom") {
		t.Fatalf("expected persistent run header in interactive output, got %q", output)
	}
	if !strings.Contains(output, "?: help") {
		t.Fatalf("expected help hint in interactive output, got %q", output)
	}
}

func scriptCommandInvocation(goos, scriptCmd, bin string) []string {
	if goos == "linux" {
		return []string{
			"-q",
			"-c",
			fmt.Sprintf("sh -c '%s' sh %q", scriptCmd, bin),
			"/dev/null",
		}
	}
	return []string{
		"-q",
		"/dev/null",
		"sh",
		"-c",
		scriptCmd,
		"sh",
		bin,
	}
}
