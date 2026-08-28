package main

import (
	"io"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/pomodoro"
	"github.com/jwp23/throwntom/v3/internal/session"
)

type noopNotifier struct{}

func (noopNotifier) PlaySound(string) error {
	return nil
}

func tempPaths(t *testing.T) core.Paths {
	t.Helper()
	dir := t.TempDir()
	return core.Paths{
		Tasks:   filepath.Join(dir, "tasks.json"),
		Session: filepath.Join(dir, "session.json"),
		Events:  filepath.Join(dir, "events.jsonl"),
	}
}

func newTestCore(t *testing.T, cfg config.Config, paths core.Paths) *core.Core {
	t.Helper()
	c, err := core.New(cfg, noopNotifier{}, paths)
	if err != nil {
		t.Fatalf("core.New: %v", err)
	}
	t.Cleanup(c.Stop)
	return c
}

func TestRunInteractiveCallbacksUsesRunInteractiveUI(t *testing.T) {
	original := runInteractiveUI
	defer func() {
		runInteractiveUI = original
	}()

	called := false
	runInteractiveUI = func(out io.Writer, in io.Reader, callbacks interactiveCallbacks) error {
		called = true
		if callbacks.StatusSnapshot == nil || callbacks.Execute == nil {
			t.Fatal("expected both callbacks to be provided")
		}
		return nil
	}

	err := runInteractiveCallbacks(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return "Idle | 00:00", engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{}, nil
		},
	})
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if !called {
		t.Fatal("expected runInteractiveUI seam to be called")
	}
}

func TestBuildCallbacksHelpLinesContainCommandsHelp(t *testing.T) {
	cfg := config.Default()
	c := newTestCore(t, cfg, tempPaths(t))

	callbacks := buildCallbacks(cfg, c)
	if len(callbacks.HelpLines) == 0 {
		t.Fatal("expected callbacks to include help lines")
	}
	foundCommandsHeader := false
	for _, line := range callbacks.HelpLines {
		if line == "commands:" {
			foundCommandsHeader = true
		}
	}
	if !foundCommandsHeader {
		t.Fatal("expected help lines to contain 'commands:' header")
	}
}

func TestBuildCallbacksExecuteDelegatesToCore(t *testing.T) {
	cfg := config.Default()
	c := newTestCore(t, cfg, tempPaths(t))

	callbacks := buildCallbacks(cfg, c)
	if callbacks.StatusSnapshot == nil {
		t.Fatal("expected status snapshot callback")
	}
	if callbacks.Execute == nil {
		t.Fatal("expected execute callback")
	}
	if len(callbacks.HeaderLines) == 0 {
		t.Fatal("expected callbacks to include persistent header lines")
	}

	resp, err := callbacks.Execute("new-cycle")
	if err != nil {
		t.Fatalf("expected nil error from execute callback, got %v", err)
	}
	if resp.Message != "New cycle started -- fresh start!" {
		t.Fatalf("expected new cycle message, got %q", resp.Message)
	}

	prompted, err := callbacks.Execute("start")
	if err != nil {
		t.Fatalf("expected nil error from execute callback, got %v", err)
	}
	if prompted.FocusPrompt == "" {
		t.Fatal("expected start to surface the core's focus prompt")
	}
}

func TestBuildCallbacksRendersStatsView(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newTestCore(t, cfg, tempPaths(t))

	resp, err := buildCallbacks(cfg, c).Execute("stats")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(resp.StatsView, "-- Today --") {
		t.Fatalf("expected rendered stats view, got %q", resp.StatsView)
	}
}

func TestBuildCallbacksSecondaryStatusRendersNextStage(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	paths := tempPaths(t)
	writeAwaitingConfirmSession(t, paths.Session)
	c := newTestCore(t, cfg, paths)

	line := buildCallbacks(cfg, c).SecondaryStatus()
	for _, want := range []string{"Next:", "short break", "5 min", "press enter to start"} {
		if !strings.Contains(line, want) {
			t.Fatalf("expected %q in %q", want, line)
		}
	}
}

func writeAwaitingConfirmSession(t *testing.T, path string) {
	t.Helper()
	data := session.Data{
		SavedAt: time.Now(),
		Timer: pomodoro.Snapshot{
			Engine: engine.Snapshot{
				State:          engine.AwaitingConfirm,
				LastPhase:      engine.Work,
				WorkSessions:   1,
				CompletedToday: 1,
				WorkDayStarted: true,
			},
		},
	}
	if err := session.Save(path, data); err != nil {
		t.Fatalf("save session: %v", err)
	}
}
