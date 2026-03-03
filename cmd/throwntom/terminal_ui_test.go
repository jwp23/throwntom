package main

import (
	"strings"
	"testing"
)

func TestRenderFrame(t *testing.T) {
	got := renderFrame("pomodoro | 24:59 | today's pomodoros=0 | pomodoros=0/4", false, "pomodoro started", "")
	if !strings.Contains(got, "status: pomodoro | 24:59 | today's pomodoros=0 | pomodoros=0/4 morning reminder pending=false") {
		t.Fatalf("unexpected status line: %q", got)
	}
	if !strings.Contains(got, "\nmessage: pomodoro started\n") {
		t.Fatalf("expected message line in frame: %q", got)
	}
	if !strings.Contains(got, "\ncommand> ") {
		t.Fatalf("expected command prompt in frame: %q", got)
	}
}

func TestRenderFrameWithWidthIncludesThreeLines(t *testing.T) {
	got := renderFrameWithWidth("idle | 00:00", false, "waiting", "sta", 0)
	if !strings.Contains(got, "status: idle | 00:00 morning reminder pending=false") {
		t.Fatalf("missing status line: %q", got)
	}
	if !strings.Contains(got, "\nmessage: waiting\n") {
		t.Fatalf("missing message line: %q", got)
	}
	if !strings.Contains(got, "\ncommand> sta") {
		t.Fatalf("missing prompt line: %q", got)
	}
}

func TestRenderFrameWithWidthDoesNotUseLegacyCursorEscape(t *testing.T) {
	got := renderFrameWithWidth("idle | 00:00", false, "", "", 0)
	if strings.Contains(got, "\x1b[3F\x1b[J") {
		t.Fatalf("expected no legacy cursor reanchor escape, got %q", got)
	}
}

func TestRenderFrameWithWidthClampsEachLineToTerminalWidth(t *testing.T) {
	got := renderFrameWithWidth(
		"idle | 00:00 | today's pomodoros=0 | pomodoros=0/4",
		false,
		"stopped and returned to idle",
		"this is a long command input",
		40,
	)

	lines := strings.Split(got, "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 lines, got %d in %q", len(lines), got)
	}
	for idx, line := range lines {
		if len([]rune(line)) > 40 {
			t.Fatalf("expected line %d to be clamped to width 40, got %d chars: %q", idx, len([]rune(line)), line)
		}
	}
}

func TestRenderFrameWithWidthAvoidsTerminalAutoWrap(t *testing.T) {
	got := renderFrameWithWidth(
		"pomodoro | 24:59 | today's pomodoros=0 | pomodoros=0/4",
		false,
		"this message should be clamped",
		"this command should be clamped",
		20,
	)

	lines := strings.Split(got, "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 lines, got %d in %q", len(lines), got)
	}
	for idx, line := range lines {
		if len([]rune(line)) >= 20 {
			t.Fatalf("expected line %d to stay below width 20 to avoid terminal auto-wrap, got %d chars: %q", idx, len([]rune(line)), line)
		}
	}
}
