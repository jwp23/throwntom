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
	"sync"
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

const (
	// fullHeaderLine is the config header rendered at the wide terminal size.
	fullHeaderLine = "33m work / 5m short / 15m long / every 4"
	// clampedHeaderLine is that same header rendered into a terminal narrowed
	// to 24 columns: the renderer trims each line to one column short of the
	// width and marks the cut with an ellipsis.
	clampedHeaderLine = "33m work / 5m short ..."
	// bracketedPasteEnable is the first sequence bubbletea writes once it owns
	// the terminal, so it marks the moment the pty leaves canonical mode.
	bracketedPasteEnable = "\x1b[?2004h"

	// waitForOutputTimeout stays well inside the go test timeout CI gives the
	// whole package, so a wait that never settles reports which observable was
	// missing instead of letting the test binary die on the watchdog. A render
	// takes well under a second, so this is generous.
	waitForOutputTimeout = 10 * time.Second
	waitForOutputPoll    = 10 * time.Millisecond
)

// resizeDriverScript resizes the pty the program is running on. stty needs the
// terminal on its stdin, and a POSIX shell gives a background job /dev/null for
// stdin, so it reads the controlling terminal directly. Each resize waits for a
// handshake file from the test rather than for a fixed delay, and no failure is
// swallowed: an stty that cannot resize produces no re-render, and the test
// waiting on that re-render fails.
const resizeDriverScript = `(
  until [ -f "$2/narrow" ]; do sleep 0.01; done
  stty cols 24 < /dev/tty
  until [ -f "$2/wide" ]; do sleep 0.01; done
  stty cols 120 < /dev/tty
) &
TERM=dumb exec "$1"`

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
	args := scriptCommandInvocation("linux", "echo hi", "/tmp/fake-bin", "/tmp/fake-handshake")
	got := strings.Join(args, " ")
	if !strings.Contains(got, " -c ") {
		t.Fatalf("expected linux invocation to include -c form, got %q", got)
	}
	if !strings.Contains(got, "/dev/null") {
		t.Fatalf("expected linux invocation to include output file path, got %q", got)
	}
}

func TestScriptCommandInvocationDarwinUsesBsdPositionalCommand(t *testing.T) {
	args := scriptCommandInvocation("darwin", "echo hi", "/tmp/fake-bin", "/tmp/fake-handshake")
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
	handshake := t.TempDir()

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	args := scriptCommandInvocation(runtime.GOOS, resizeDriverScript, bin, handshake)
	cmd := exec.CommandContext(ctx, "script", args...)
	cmd.Env = isolatedHomeEnv(t, smokeConfig)
	out := &syncBuffer{}
	cmd.Stdout = out
	cmd.Stderr = out
	stdin, err := cmd.StdinPipe()
	if err != nil {
		t.Fatalf("stdin pipe: %v", err)
	}

	if err := cmd.Start(); err != nil {
		t.Fatalf("start script command: %v", err)
	}

	// Every step below waits on something the run actually did. The interrupt
	// byte in particular must not be written until bubbletea has taken the pty
	// out of canonical mode, because until then the line discipline reads 0x03
	// as INTR and kills the process group before the program sees a keystroke.
	waitForOutput(t, out, bracketedPasteEnable, "terminal switched to raw mode")
	waitForOutput(t, out, fullHeaderLine, "initial render")

	releaseResize(t, handshake, "narrow")
	waitForOutput(t, out, clampedHeaderLine, "re-render clamped by the narrow resize")

	releaseResize(t, handshake, "wide")
	waitForOutputCount(t, out, fullHeaderLine, 2, "re-render restored by the wide resize")

	if _, err := stdin.Write([]byte{0x03}); err != nil {
		t.Fatalf("write interrupt: %v", err)
	}
	if err := stdin.Close(); err != nil {
		t.Fatalf("close stdin: %v", err)
	}

	if err := cmd.Wait(); err != nil {
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
}

func scriptCommandInvocation(goos, scriptCmd, bin, handshake string) []string {
	if goos == "linux" {
		return []string{
			"-q",
			"-c",
			fmt.Sprintf("sh -c '%s' sh %q %q", scriptCmd, bin, handshake),
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
		handshake,
	}
}

// releaseResize hands the driver script the go-ahead for one resize step. The
// script waits for these files instead of sleeping, so each resize lands only
// after the test has seen the run reach the state the resize is meant to probe.
func releaseResize(t *testing.T, handshake, step string) {
	t.Helper()

	if err := os.WriteFile(filepath.Join(handshake, step), nil, 0o600); err != nil {
		t.Fatalf("release %s resize: %v", step, err)
	}
}

func waitForOutput(t *testing.T, out *syncBuffer, want, what string) {
	t.Helper()

	waitForOutputCount(t, out, want, 1, what)
}

// waitForOutputCount blocks until the run has written want at least count
// times. Waiting on the output itself is what keeps this test honest: if a
// resize never reaches the program, the expected re-render never arrives and
// the test fails instead of quietly asserting nothing.
func waitForOutputCount(t *testing.T, out *syncBuffer, want string, count int, what string) {
	t.Helper()

	deadline := time.Now().Add(waitForOutputTimeout)
	for {
		got := out.String()
		if strings.Count(got, want) >= count {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("timed out after %s waiting for %s (%q x%d), got %q",
				waitForOutputTimeout, what, want, count, got)
		}
		time.Sleep(waitForOutputPoll)
	}
}

// syncBuffer collects the run's output for a reader in another goroutine: the
// test polls it while os/exec is still writing into it.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
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
