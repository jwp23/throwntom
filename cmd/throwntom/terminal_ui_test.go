package main

import (
	"strings"
	"testing"

	"github.com/charmbracelet/x/ansi"
	"github.com/jwp23/throwntom/v2/internal/engine"
)

func TestRenderThemedFrameIncludesThreeLines(t *testing.T) {
	got := renderThemedFrame("Idle  Today: 0  Cycle: 0/4", engine.Idle, false, "waiting", false, "sta", 0, true)
	if !strings.Contains(got, "Idle") {
		t.Fatalf("missing status content: %q", got)
	}
	if !strings.Contains(got, "\nwaiting\n") {
		t.Fatalf("missing message line: %q", got)
	}
	if !strings.Contains(got, "\n> sta") {
		t.Fatalf("missing prompt line: %q", got)
	}
}

func TestRenderThemedFrameDoesNotUseLegacyCursorEscape(t *testing.T) {
	got := renderThemedFrame("Idle  Today: 0  Cycle: 0/4", engine.Idle, false, "", false, "", 0, true)
	if strings.Contains(got, "\x1b[3F\x1b[J") {
		t.Fatalf("expected no legacy cursor reanchor escape, got %q", got)
	}
}

func TestRenderThemedFrameClampsEachLineToTerminalWidth(t *testing.T) {
	got := renderThemedFrame(
		"Idle  Today: 0  Cycle: 0/4",
		engine.Idle,
		false,
		"Stopped. Back to idle.",
		false,
		"this is a long command input",
		40,
		false,
	)

	lines := strings.Split(got, "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 lines, got %d in %q", len(lines), got)
	}
	for idx, line := range lines {
		if ansi.StringWidth(line) > 39 {
			t.Fatalf("expected line %d to be clamped to width 40, got %d visible chars: %q", idx, ansi.StringWidth(line), line)
		}
	}
}

func TestRenderThemedFrameAvoidsTerminalAutoWrap(t *testing.T) {
	got := renderThemedFrame(
		"Pomodoro  24:59  Today: 0  Cycle: 0/4",
		engine.Work,
		false,
		"this message should be clamped",
		false,
		"this command should be clamped",
		20,
		false,
	)

	lines := strings.Split(got, "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 lines, got %d in %q", len(lines), got)
	}
	for idx, line := range lines {
		if ansi.StringWidth(line) >= 20 {
			t.Fatalf("expected line %d to stay below width 20 to avoid terminal auto-wrap, got %d visible chars: %q", idx, ansi.StringWidth(line), line)
		}
	}
}
