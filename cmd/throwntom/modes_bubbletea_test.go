package main

import (
	"fmt"
	"io"
	"testing"

	"github.com/jwp23/throwntom/internal/config"
	"github.com/jwp23/throwntom/internal/notifier"
)

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
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00", false
		},
		Execute: func(string) (daemonControlResponse, error) {
			return daemonControlResponse{}, nil
		},
	})
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if !called {
		t.Fatal("expected runInteractiveUI seam to be called")
	}
}

func TestLocalModeCallbacksHelpLinesContainCommandsHelp(t *testing.T) {
	cfg := config.Default()
	core := newDaemonCore(cfg, notifier.NewTestNotifier(func(string, ...string) error {
		return fmt.Errorf("unused")
	}))

	callbacks := localModeCallbacks(cfg, core)
	if len(callbacks.HelpLines) == 0 {
		t.Fatal("expected local mode callbacks to include help lines")
	}
	foundCommandsHeader := false
	for _, line := range callbacks.HelpLines {
		if line == "daemon commands:" {
			foundCommandsHeader = true
		}
	}
	if !foundCommandsHeader {
		t.Fatal("expected help lines to contain 'daemon commands:' header")
	}
}

func TestLocalModeCallbacksExecuteDelegatesToCore(t *testing.T) {
	cfg := config.Default()
	core := newDaemonCore(cfg, notifier.NewTestNotifier(func(string, ...string) error {
		return fmt.Errorf("unused")
	}))

	callbacks := localModeCallbacks(cfg, core)
	if callbacks.StatusSnapshot == nil {
		t.Fatal("expected status snapshot callback")
	}
	if callbacks.Execute == nil {
		t.Fatal("expected execute callback")
	}
	if len(callbacks.HeaderLines) == 0 {
		t.Fatal("expected local mode callbacks to include persistent header lines")
	}

	resp, err := callbacks.Execute("start")
	if err != nil {
		t.Fatalf("expected nil error from execute callback, got %v", err)
	}
	if resp.Message != "pomodoro started" {
		t.Fatalf("expected start message, got %q", resp.Message)
	}
}
