package main

import (
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v2/internal/engine"
)

func TestStateIconEmojiMode(t *testing.T) {
	tests := []struct {
		state engine.State
		emoji string
		plain string
	}{
		{engine.Work, "\U0001F345", "*"},
		{engine.ShortBreak, "\u2615", "~"},
		{engine.LongBreak, "\U0001F33F", "~"},
		{engine.Idle, "\U0001F331", "-"},
		{engine.Paused, "\u23F8\uFE0F", "||"},
		{engine.AwaitingConfirm, "\U0001F514", "!"},
	}
	for _, tt := range tests {
		got := stateIcon(tt.state, true)
		if got != tt.emoji {
			t.Errorf("stateIcon(%s, emoji=true) = %q, want %q", tt.state, got, tt.emoji)
		}
		got = stateIcon(tt.state, false)
		if got != tt.plain {
			t.Errorf("stateIcon(%s, emoji=false) = %q, want %q", tt.state, got, tt.plain)
		}
	}
}

func TestMorningIcon(t *testing.T) {
	if got := morningIcon(true); got != "\U0001F514" {
		t.Errorf("morningIcon(true) = %q, want bell emoji", got)
	}
	if got := morningIcon(false); got != "[!]" {
		t.Errorf("morningIcon(false) = %q, want [!]", got)
	}
}

func TestStateStyleReturnsNonEmpty(t *testing.T) {
	for _, s := range []engine.State{engine.Idle, engine.Work, engine.ShortBreak, engine.LongBreak, engine.Paused, engine.AwaitingConfirm} {
		style := stateStyle(s)
		rendered := style.Render("test")
		if rendered == "" {
			t.Errorf("stateStyle(%s) rendered empty string", s)
		}
	}
}

func TestRenderThemedFrame(t *testing.T) {
	frame := renderThemedFrame("Pomodoro  24:35  Today: 0  Cycle: 0/4", engine.Work, false, "started", false, "st", 0, true)
	if !strings.Contains(frame, "Pomodoro") {
		t.Fatalf("expected status line in themed frame, got %q", frame)
	}
	if !strings.Contains(frame, "started") {
		t.Fatalf("expected message in themed frame, got %q", frame)
	}
	if !strings.Contains(frame, "> st") {
		t.Fatalf("expected prompt in themed frame, got %q", frame)
	}
}

func TestRenderThemedFrameMorningIndicator(t *testing.T) {
	frame := renderThemedFrame("Idle  Today: 0  Cycle: 0/4", engine.Idle, true, "", false, "", 0, true)
	if !strings.Contains(frame, "\U0001F514") {
		t.Fatalf("expected morning bell icon when morning pending, got %q", frame)
	}
}

func TestClampANSILine(t *testing.T) {
	plain := "hello world"
	clamped := clampANSILine(plain, 8)
	if len([]rune(clamped)) > 7 {
		t.Fatalf("expected clamped to 7 visible chars, got %q", clamped)
	}
}

func TestClampANSILineZeroWidthPassthrough(t *testing.T) {
	line := "some long line"
	if got := clampANSILine(line, 0); got != line {
		t.Fatalf("expected passthrough at width 0, got %q", got)
	}
}
