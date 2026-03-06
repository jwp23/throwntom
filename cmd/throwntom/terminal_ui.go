package main

import (
	"fmt"
)

func renderFrameWithWidth(statusLine string, morningPending bool, message string, input string, width int) string {
	return fmt.Sprintf(
		"%s\n%s\n%s",
		clampTerminalLine(fmt.Sprintf("status: %s morning reminder pending=%t", statusLine, morningPending), width),
		clampTerminalLine("message: "+message, width),
		clampTerminalLine("command> "+input, width),
	)
}

func clampTerminalLine(line string, width int) string {
	if width <= 0 {
		return line
	}
	if width == 1 {
		return ""
	}
	max := width - 1
	runes := []rune(line)
	if len(runes) <= max {
		return line
	}
	if max <= 3 {
		return string(runes[:max])
	}
	return string(runes[:max-3]) + "..."
}
