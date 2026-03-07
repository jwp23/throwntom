package main

import (
	"strings"
	"testing"

	"github.com/charmbracelet/x/ansi"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

func TestRenderThemedFrameIncludesThreeLines(t *testing.T) {
	got := renderThemedFrame(frameInput{
		StatusLine: testStatusIdle,
		State:      engine.Idle,
		Message:    "waiting",
		Input:      "sta",
		Emoji:      true,
	})
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
	got := renderThemedFrame(frameInput{
		StatusLine: testStatusIdle,
		State:      engine.Idle,
		Emoji:      true,
	})
	if strings.Contains(got, "\x1b[3F\x1b[J") {
		t.Fatalf("expected no legacy cursor reanchor escape, got %q", got)
	}
}

func TestRenderThemedFrameClampsEachLineToTerminalWidth(t *testing.T) {
	got := renderThemedFrame(frameInput{
		StatusLine: testStatusIdle,
		State:      engine.Idle,
		Message:    "Stopped. Back to idle.",
		Input:      "this is a long command input",
		Width:      40,
	})

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
	got := renderThemedFrame(frameInput{
		StatusLine: "Pomodoro  24:59  Today: 0  Cycle: 0/4",
		State:      engine.Work,
		Message:    "this message should be clamped",
		Input:      "this command should be clamped",
		Width:      20,
	})

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
