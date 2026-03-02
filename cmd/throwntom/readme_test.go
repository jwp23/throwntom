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
		"throwntom daemon",
		"throwntom shell",
		"throwntom ctl status",
		"packaging/systemd/throwntom.service",
		"packaging/launchd/io.github.jwp23.throwntom.plist",
		"./packaging/install-service.sh",
		"go vet ./...",
		"golangci-lint run ./...",
		"`start`",
		"`new-cycle`",
		"`pause`",
		"`resume`",
		"`stop`",
		"`confirm`",
		"`snooze <duration>`",
		"`skip-today`",
		"`status`",
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

func TestGolangCILintConfigUsesV2Schema(t *testing.T) {
	content, err := os.ReadFile("../../.golangci.yml")
	if err != nil {
		t.Fatalf("read .golangci.yml: %v", err)
	}
	cfg := string(content)

	for _, expected := range []string{
		`version: "2"`,
		"default: none",
		"settings:",
		"cyclop:",
		"max-complexity: 15",
		"package-average: 10.0",
	} {
		if !strings.Contains(cfg, expected) {
			t.Fatalf("expected .golangci.yml to include %q", expected)
		}
	}

	for _, deprecated := range []string{
		"disable-all: true",
		"linters-settings:",
	} {
		if strings.Contains(cfg, deprecated) {
			t.Fatalf("did not expect .golangci.yml to include %q", deprecated)
		}
	}
}
