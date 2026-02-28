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

func TestRenderInPlaceStatusUpdateSequence(t *testing.T) {
	got := renderInPlaceStatusLine("idle | 00:00 | today's pomodoros=0 | pomodoros=0/4", true, "waiting")
	if !strings.Contains(got, "\x1b[s") {
		t.Fatalf("expected save-cursor sequence, got %q", got)
	}
	if !strings.Contains(got, "\x1b[2A") {
		t.Fatalf("expected move-up sequence for status row, got %q", got)
	}
	if !strings.Contains(got, "\x1b[u") {
		t.Fatalf("expected restore-cursor sequence, got %q", got)
	}
	if !strings.Contains(got, "status: idle | 00:00 | today's pomodoros=0 | pomodoros=0/4 morning reminder pending=true") {
		t.Fatalf("unexpected status payload: %q", got)
	}
	if !strings.Contains(got, "message: waiting") {
		t.Fatalf("unexpected message payload: %q", got)
	}
}

func TestRenderInPlaceFrameRewritesAllRows(t *testing.T) {
	got := renderInPlaceFrame("idle | 00:00 | today's pomodoros=0 | pomodoros=0/4", false, "resumed", "")
	if strings.Count(got, "\x1b[1A") != 3 {
		t.Fatalf("expected to move up three rows before redraw, got %q", got)
	}
	if strings.Count(got, "\x1b[2K") != 3 {
		t.Fatalf("expected to clear three rows before redraw, got %q", got)
	}
	if !strings.Contains(got, "message: resumed") {
		t.Fatalf("expected message payload in frame redraw, got %q", got)
	}
}
