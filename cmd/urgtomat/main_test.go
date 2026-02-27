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

