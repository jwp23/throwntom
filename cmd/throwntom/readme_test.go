package main

import (
	"os"
	"strings"
	"testing"
)

func TestREADMEIncludesInstallAndDaemonCommands(t *testing.T) {
	content, err := os.ReadFile("../../README.md")
	if err != nil {
		t.Fatalf("read README.md: %v", err)
	}

	readme := string(content)

	for _, expected := range []string{
		"go install ./cmd/throwntom",
		"`start`",
		"`pause`",
		"`resume`",
		"`stop`",
		"`confirm`",
		"`snooze <duration>`",
		"`skip-today`",
		"`test-sound`",
		"`quit`",
		"`exit`",
	} {
		if !strings.Contains(readme, expected) {
			t.Fatalf("expected README to include %q", expected)
		}
	}
}
