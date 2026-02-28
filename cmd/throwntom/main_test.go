package main

import (
	"strings"
	"testing"
)

func TestDaemonCommandHelpIncludesNewControls(t *testing.T) {
	help := daemonCommandsHelp()
	for _, cmd := range []string{"pause", "resume", "stop", "test-sound", "help"} {
		if !strings.Contains(help, cmd) {
			t.Fatalf("expected %q in daemon command help: %s", cmd, help)
		}
	}
}

func TestShouldRenderStatus(t *testing.T) {
	if !shouldRenderStatus(false) {
		t.Fatalf("expected status render while waiting for input")
	}
	if shouldRenderStatus(true) {
		t.Fatalf("expected status render suppression only while processing command")
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
