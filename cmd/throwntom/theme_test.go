package main

import (
	"strings"
	"testing"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/task"
)

const testBellEmoji = "\U0001F514"

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
		{engine.AwaitingConfirm, testBellEmoji, "!"},
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
	if got := morningIcon(true); got != testBellEmoji {
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
	frame := renderThemedFrame(frameInput{
		StatusLine: "Pomodoro  24:35  Today: 0  Cycle: 0/4",
		State:      engine.Work,
		Message:    "started",
		Input:      "st",
		Emoji:      true,
	})
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
	frame := renderThemedFrame(frameInput{
		StatusLine:     testStatusIdle,
		State:          engine.Idle,
		MorningPending: true,
		Emoji:          true,
	})
	if !strings.Contains(frame, testBellEmoji) {
		t.Fatalf("expected morning bell icon when morning pending, got %q", frame)
	}
}

func TestRenderThemedFrameMorningIndicatorMentionsSnooze(t *testing.T) {
	frame := renderThemedFrame(frameInput{
		StatusLine:     testStatusIdle,
		State:          engine.Idle,
		MorningPending: true,
		Emoji:          true,
	})
	if !strings.Contains(frame, "snooze 10m") {
		t.Fatalf("expected morning-pending hint to show a typeable snooze command, got %q", frame)
	}
}

func TestNextStageLabelContainsPhaseAndDuration(t *testing.T) {
	tests := []struct {
		next        engine.State
		duration    time.Duration
		wantPhrase  string
		wantMinutes string
	}{
		{engine.Work, 25 * time.Minute, "pomodoro", "25 min"},
		{engine.ShortBreak, 5 * time.Minute, "short break", "5 min"},
		{engine.LongBreak, 15 * time.Minute, "long break", "15 min"},
	}
	for _, tc := range tests {
		got := nextStageLabel(tc.next, tc.duration)
		if !strings.Contains(got, "Next:") {
			t.Errorf("nextStageLabel(%s) missing 'Next:' prefix: %q", tc.next, got)
		}
		if !strings.Contains(got, tc.wantPhrase) {
			t.Errorf("nextStageLabel(%s) missing %q, got %q", tc.next, tc.wantPhrase, got)
		}
		if !strings.Contains(got, tc.wantMinutes) {
			t.Errorf("nextStageLabel(%s) missing duration %q, got %q", tc.next, tc.wantMinutes, got)
		}
		if !strings.Contains(got, "press enter to start") {
			t.Errorf("nextStageLabel(%s) missing action hint, got %q", tc.next, got)
		}
		if !strings.Contains(got, "snooze 10m") {
			t.Errorf("nextStageLabel(%s) should show a typeable snooze command, got %q", tc.next, got)
		}
	}
}

func TestNextStageLabelColorsPhaseWithPhaseStyle(t *testing.T) {
	// The phase phrase should be wrapped in its own color (distinct from the
	// surrounding AwaitingConfirm amber), so that when the full status line
	// is rendered in amber, the phase still stands out in its own color.
	got := nextStageLabel(engine.ShortBreak, 5*time.Minute)
	coloredPhrase := stateStyle(engine.ShortBreak).Render("short break")
	// Strip the trailing reset so we can search for the open sequence.
	openSeq := strings.SplitAfter(coloredPhrase, "short break")[0]
	if !strings.Contains(got, openSeq) {
		t.Errorf("expected phase-color ANSI around phrase, got %q (wanted substring %q)", got, openSeq)
	}
	// Sanity: label is non-empty and longer than the plain form.
	plain := "Next: short break (5 min) — press enter to start"
	if lipgloss.Width(got) < lipgloss.Width(plain) {
		t.Errorf("expected rendered label to be at least as wide as plain form, got %d < %d", lipgloss.Width(got), lipgloss.Width(plain))
	}
}

func TestNextStageLabelIdleFallback(t *testing.T) {
	got := nextStageLabel(engine.Idle, 0)
	if !strings.Contains(got, "press enter to start") {
		t.Errorf("fallback label should still prompt for enter, got %q", got)
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

func TestFormatFocusLines(t *testing.T) {
	lines := formatFocusLines([]task.Task{{ID: 7, Description: "write ADR"}}, false)
	if len(lines) != 2 || lines[0] != "* Focus:" || lines[1] != "  1. write ADR" {
		t.Fatalf("unexpected lines %q", lines)
	}
	if formatFocusLines(nil, false) != nil {
		t.Fatal("expected nil for no focused tasks")
	}
}
