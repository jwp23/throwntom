package main

import (
	"fmt"
	"io"
	"sync"
)

type terminalUI struct {
	mu      sync.Mutex
	out     io.Writer
	enabled bool
	message string
	width   int
}

func newTerminalUI(out io.Writer) *terminalUI {
	return &terminalUI{out: out}
}

func (u *terminalUI) ShowFrame(statusLine string, morningPending bool) {
	u.ShowFrameWithInput(statusLine, morningPending, "")
}

func (u *terminalUI) ShowFrameWithInput(statusLine string, morningPending bool, input string) {
	u.mu.Lock()
	defer u.mu.Unlock()
	if !u.enabled {
		_, _ = io.WriteString(u.out, renderFrameWithWidth(statusLine, morningPending, u.message, input, u.width))
		u.enabled = true
		return
	}
	_, _ = io.WriteString(u.out, renderFullFrameWithWidth(statusLine, morningPending, u.message, input, u.width))
	u.enabled = true
}

func (u *terminalUI) UpdateStatus(statusLine string, morningPending bool) {
	u.ShowFrameWithInput(statusLine, morningPending, "")
}

func (u *terminalUI) Println(msg string) {
	u.mu.Lock()
	defer u.mu.Unlock()
	if !u.enabled {
		_, _ = io.WriteString(u.out, msg)
		_, _ = io.WriteString(u.out, "\n")
		return
	}
	u.message = msg
}

func renderFrame(statusLine string, morningPending bool, message string, input string) string {
	return renderFrameWithWidth(statusLine, morningPending, message, input, 0)
}

func renderFullFrame(statusLine string, morningPending bool, message string, input string) string {
	return renderFullFrameWithWidth(statusLine, morningPending, message, input, 0)
}

func renderFrameWithWidth(statusLine string, morningPending bool, message string, input string, width int) string {
	return fmt.Sprintf(
		"%s\n%s\n%s",
		clampTerminalLine(fmt.Sprintf("status: %s morning reminder pending=%t", statusLine, morningPending), width),
		clampTerminalLine("message: "+message, width),
		clampTerminalLine("command> "+input, width),
	)
}

func renderFullFrameWithWidth(statusLine string, morningPending bool, message string, input string, width int) string {
	return "\x1b[3F\x1b[J" + renderFrameWithWidth(statusLine, morningPending, message, input, width)
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

func (u *terminalUI) SetWidth(width int) {
	u.mu.Lock()
	defer u.mu.Unlock()
	if width < 0 {
		width = 0
	}
	u.width = width
}
