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
		"go install github.com/jwp23/throwntom/cmd/throwntom@latest",
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

func TestGoModulePathIsPublishable(t *testing.T) {
	content, err := os.ReadFile("../../go.mod")
	if err != nil {
		t.Fatalf("read go.mod: %v", err)
	}
	if !strings.Contains(string(content), "module github.com/jwp23/throwntom") {
		t.Fatalf("expected go.mod module path to be github.com/jwp23/throwntom")
	}
}
