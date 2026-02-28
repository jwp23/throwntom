package main

import (
	"strings"
	"testing"
)

func TestRenderFrame(t *testing.T) {
	got := renderFrame("pomodoro | 24:59 | today_total=0 | pomodoros_done=0/4", false, "")
	if !strings.Contains(got, "status: pomodoro | 24:59 | today_total=0 | pomodoros_done=0/4 morning_pending=false") {
		t.Fatalf("unexpected status line: %q", got)
	}
	if !strings.Contains(got, "\ncommand> ") {
		t.Fatalf("expected command prompt in frame: %q", got)
	}
}

func TestRenderInPlaceStatusUpdateSequence(t *testing.T) {
	got := renderInPlaceStatusLine("idle | 00:00 | today_total=0 | pomodoros_done=0/4", true)
	if !strings.Contains(got, "\x1b[s") {
		t.Fatalf("expected save-cursor sequence, got %q", got)
	}
	if !strings.Contains(got, "\x1b[u") {
		t.Fatalf("expected restore-cursor sequence, got %q", got)
	}
	if !strings.Contains(got, "status: idle | 00:00 | today_total=0 | pomodoros_done=0/4 morning_pending=true") {
		t.Fatalf("unexpected status payload: %q", got)
	}
}
