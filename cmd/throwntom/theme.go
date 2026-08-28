package main

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/task"
)

var (
	colorOrange    = lipgloss.AdaptiveColor{Light: "#D75F00", Dark: "#FF8C00"}
	colorGreen     = lipgloss.AdaptiveColor{Light: "#228B22", Dark: "#32CD32"}
	colorDeepGreen = lipgloss.AdaptiveColor{Light: "#006400", Dark: "#228B22"}
	colorYellow    = lipgloss.AdaptiveColor{Light: "#B8860B", Dark: "#FFD700"}
	colorDim       = lipgloss.AdaptiveColor{Light: "#808080", Dark: "#666666"}
	colorRed       = lipgloss.AdaptiveColor{Light: "#CC0000", Dark: "#FF4444"}
	colorAmber     = lipgloss.AdaptiveColor{Light: "#CC7000", Dark: "#FFA500"}
)

func stateIcon(state engine.State, emoji bool) string {
	if emoji {
		switch state {
		case engine.Work:
			return "\U0001F345"
		case engine.ShortBreak:
			return "\u2615"
		case engine.LongBreak:
			return "\U0001F33F"
		case engine.Idle:
			return "\U0001F331"
		case engine.Paused:
			return "\u23F8\uFE0F"
		case engine.AwaitingConfirm:
			return "\U0001F514"
		default:
			return "\U0001F331"
		}
	}
	switch state {
	case engine.Work:
		return "*"
	case engine.ShortBreak, engine.LongBreak:
		return "~"
	case engine.Idle:
		return "-"
	case engine.Paused:
		return "||"
	case engine.AwaitingConfirm:
		return "!"
	default:
		return "-"
	}
}

func morningIcon(emoji bool) string {
	if emoji {
		return "\U0001F514"
	}
	return "[!]"
}

func stateStyle(state engine.State) lipgloss.Style {
	switch state {
	case engine.Work:
		return lipgloss.NewStyle().Foreground(colorOrange)
	case engine.ShortBreak:
		return lipgloss.NewStyle().Foreground(colorGreen)
	case engine.LongBreak:
		return lipgloss.NewStyle().Foreground(colorDeepGreen)
	case engine.Idle:
		return lipgloss.NewStyle().Foreground(colorYellow)
	case engine.Paused:
		return lipgloss.NewStyle().Foreground(colorDim)
	case engine.AwaitingConfirm:
		return lipgloss.NewStyle().Foreground(colorAmber)
	default:
		return lipgloss.NewStyle().Foreground(colorYellow)
	}
}

func formatFocusLines(focused []task.Task, emoji bool) []string {
	if len(focused) == 0 {
		return nil
	}
	lines := []string{stateIcon(engine.Work, emoji) + " Focus:"}
	for i, tk := range focused {
		lines = append(lines, fmt.Sprintf("  %d. %s", i+1, tk.Description))
	}
	return lines
}

func nextStageLabel(next engine.State, duration time.Duration) string {
	phrase := core.FriendlyStateName(next)
	minutes := int(duration / time.Minute)
	colored := stateStyle(next).Render(fmt.Sprintf("%s (%d min)", phrase, minutes))
	return fmt.Sprintf("Next: %s — press enter to start, or snooze to hold your place", colored)
}

func morningPendingHint() string {
	return "Reminder waiting — start to begin, snooze to wait, or skip-today to silence it"
}

type frameInput struct {
	StatusLine     string
	Secondary      string
	State          engine.State
	MorningPending bool
	Message        string
	IsError        bool
	Input          string
	Width          int
	Emoji          bool
}

func renderThemedFrame(f frameInput) string {
	icon := stateIcon(f.State, f.Emoji)
	style := stateStyle(f.State)
	statusRendered := fmt.Sprintf("%s %s", icon, style.Render(f.StatusLine))
	if f.MorningPending {
		statusRendered += " " + morningIcon(f.Emoji)
	}

	var msgLine string
	if f.Message != "" {
		if f.IsError {
			msgLine = lipgloss.NewStyle().Foreground(colorRed).Render(f.Message)
		} else {
			msgLine = f.Message
		}
	}

	promptLine := "> " + f.Input

	var parts []string
	parts = append(parts, clampANSILine(statusRendered, f.Width))
	if f.Secondary != "" {
		parts = append(parts, clampANSILine(f.Secondary, f.Width))
	} else if f.MorningPending {
		parts = append(parts, clampANSILine(morningPendingHint(), f.Width))
	}
	for _, line := range strings.Split(msgLine, "\n") {
		parts = append(parts, clampANSILine(line, f.Width))
	}
	parts = append(parts, clampANSILine(promptLine, f.Width))
	return strings.Join(parts, "\n")
}

func clampANSILine(line string, width int) string {
	if width <= 0 {
		return line
	}
	if width == 1 {
		return ""
	}
	max := width - 1
	visibleWidth := ansi.StringWidth(line)
	if visibleWidth <= max {
		return line
	}
	if max <= 3 {
		return ansi.Truncate(line, max, "")
	}
	return ansi.Truncate(line, max, "...")
}
