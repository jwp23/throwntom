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

// Each colour is a light-terminal / dark-terminal pair chosen to meet WCAG AA
// (4.5:1) on white and on black, and to keep rest (teal, blue) off the red-green
// axis so the states stay distinct for colour-blind users.
var (
	colorOrange = lipgloss.AdaptiveColor{Light: "#B94A0E", Dark: "#F68C31"}
	colorTeal   = lipgloss.AdaptiveColor{Light: "#0E6F73", Dark: "#3FC1C9"}
	colorBlue   = lipgloss.AdaptiveColor{Light: "#1F4E9C", Dark: "#7AA6F5"}
	colorYellow = lipgloss.AdaptiveColor{Light: "#6B5E00", Dark: "#E6C84A"}
	colorDim    = lipgloss.AdaptiveColor{Light: "#6B6B6B", Dark: "#9A9A9A"}
	colorRed    = lipgloss.AdaptiveColor{Light: "#B3001B", Dark: "#FF5C5C"}
	colorTomato = lipgloss.AdaptiveColor{Light: "#A8330F", Dark: "#FF7A59"}
)

// palette lists every colour the TUI paints, by role.
func palette() map[string]lipgloss.AdaptiveColor {
	return map[string]lipgloss.AdaptiveColor{
		"work":             colorOrange,
		"short-break":      colorTeal,
		"long-break":       colorBlue,
		"idle":             colorYellow,
		"paused":           colorDim,
		"awaiting-confirm": colorTomato,
		"error":            colorRed,
	}
}

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
		return lipgloss.NewStyle().Foreground(colorTeal)
	case engine.LongBreak:
		return lipgloss.NewStyle().Foreground(colorBlue)
	case engine.Idle:
		return lipgloss.NewStyle().Foreground(colorYellow)
	case engine.Paused:
		return lipgloss.NewStyle().Foreground(colorDim)
	case engine.AwaitingConfirm:
		return lipgloss.NewStyle().Foreground(colorTomato)
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
	return fmt.Sprintf("Next: %s — press enter to start, or snooze 10m to hold your place", colored)
}

func morningPendingHint() string {
	return "Reminder waiting — start to begin, snooze 10m to wait, or skip-today to silence it"
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
