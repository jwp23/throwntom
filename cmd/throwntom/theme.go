package main

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/ansi"
	"github.com/jwp23/throwntom/v2/internal/engine"
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

func renderThemedFrame(statusLine string, state engine.State, morningPending bool, message string, isError bool, input string, width int, emoji bool) string {
	icon := stateIcon(state, emoji)
	style := stateStyle(state)
	statusRendered := fmt.Sprintf("%s %s", icon, style.Render(statusLine))
	if morningPending {
		statusRendered += " " + morningIcon(emoji)
	}

	var msgLine string
	if message != "" {
		if isError {
			msgLine = lipgloss.NewStyle().Foreground(colorRed).Render(message)
		} else {
			msgLine = message
		}
	}

	promptLine := "> " + input

	return fmt.Sprintf(
		"%s\n%s\n%s",
		clampANSILine(statusRendered, width),
		clampANSILine(msgLine, width),
		clampANSILine(promptLine, width),
	)
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
