package main

import (
	"strings"
	"testing"
)

func TestDaemonCommandHelpIncludesNewControls(t *testing.T) {
	help := daemonCommandsHelp()
	for _, cmd := range []string{"pause", "resume", "stop", "help"} {
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

func TestShouldStartLiveStatusRenderer(t *testing.T) {
	if shouldStartLiveStatusRenderer(true, true) {
		t.Fatalf("expected interactive tty mode to disable live status renderer")
	}
	if !shouldStartLiveStatusRenderer(false, true) {
		t.Fatalf("expected non-tty stdin to enable live status renderer")
	}
	if !shouldStartLiveStatusRenderer(true, false) {
		t.Fatalf("expected non-tty stdout to enable live status renderer")
	}
}
