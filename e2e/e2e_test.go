//go:build e2e

package e2e_test

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"
)

// smokeConfig overrides work_minutes so the interactive output proves which
// config the binary read, and disables the morning reminder so the run does
// not depend on the weekday or the time of day.
const smokeConfig = `morning_reminder_pending = false

[pomodoro]
work_minutes = 33
`

// clampedHeaderLine is the config header rendered into a terminal narrowed to
// resizeNarrowCols: clampANSILine trims it to one column short of the width and
// marks the cut with an ellipsis.
const clampedHeaderLine = "33m work / 5m short ..."

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

// isolatedHomeEnv points the binary under test at a throwntom config directory
// owned by the test. Without it the binary reads and rewrites the developer's
// real ~/.config/throwntom, so live session state leaks into assertions and a
// test run can clobber a running pomodoro. An empty configTOML leaves the
// directory absent so the binary falls back to its built-in defaults.
func isolatedHomeEnv(t *testing.T, configTOML string) []string {
	t.Helper()

	home := t.TempDir()
	if configTOML != "" {
		dir := filepath.Join(home, ".config", "throwntom")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatalf("create isolated config dir: %v", err)
		}
		if err := os.WriteFile(filepath.Join(dir, "config.toml"), []byte(configTOML), 0o600); err != nil {
			t.Fatalf("write isolated config: %v", err)
		}
	}
	return append(os.Environ(), "HOME="+home)
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
	cmd.Env = isolatedHomeEnv(t, "")
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
	cmd.Env = isolatedHomeEnv(t, "")
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
	cmd.Env = isolatedHomeEnv(t, "")
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
TERM=dumb exec "$1"`

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	args := scriptCommandInvocation(runtime.GOOS, scriptCmd, bin)
	cmd := exec.CommandContext(ctx, "script", args...)
	cmd.Env = isolatedHomeEnv(t, smokeConfig)
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
	if !strings.Contains(output, "33m work") {
		t.Fatalf("expected header from the test-owned config, got %q", output)
	}
	// The absence assertions above only mean anything if a resize actually
	// reached the program. A narrowed terminal clamps the header, so the
	// clamped line is the proof that the run was resized at all.
	if !strings.Contains(output, clampedHeaderLine) {
		t.Fatalf("expected a re-render clamped by the narrow resize, got %q", output)
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

// buildDaemonBinary builds throwntomd, the binary that owns the config file's
// lifecycle: it writes the documented template when the user has no config.
func buildDaemonBinary(t *testing.T) string {
	t.Helper()

	binName := "throwntomd-e2e"
	if runtime.GOOS == "windows" {
		binName += ".exe"
	}
	binPath := filepath.Join(t.TempDir(), binName)
	cmd := exec.Command("go", "build", "-o", binPath, "../cmd/throwntomd")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("build daemon binary: %v\n%s", err, out)
	}
	return binPath
}

// A path the user named is never created for them: a typo in --config must
// fail loudly rather than quietly start the daemon on defaults and write a
// template somewhere they will never look.
func TestDaemonRefusesToCreateANamedConfigPath(t *testing.T) {
	bin := buildDaemonBinary(t)
	missingPath := filepath.Join(t.TempDir(), "typo.toml")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, bin, "--config", missingPath)
	cmd.Env = isolatedHomeEnv(t, "")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()

	if err == nil {
		t.Fatal("expected non-zero exit for a config path that does not exist")
	}
	output := stderr.String()
	if !strings.Contains(output, "config error:") {
		t.Fatalf("expected config error output, got %q", output)
	}
	if _, statErr := os.Stat(missingPath); statErr == nil {
		t.Fatal("expected the named path to be left alone, but a config was written there")
	}
}
