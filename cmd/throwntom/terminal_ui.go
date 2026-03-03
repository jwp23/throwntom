package main

import (
	"fmt"
)

func renderFrame(statusLine string, morningPending bool, message string, input string) string {
	return renderFrameWithWidth(statusLine, morningPending, message, input, 0)
}

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
	runes := []rune(line)
	if len(runes) <= width {
		return line
	}
	if width <= 3 {
		return string(runes[:width])
	}
	return string(runes[:width-3]) + "..."
}
