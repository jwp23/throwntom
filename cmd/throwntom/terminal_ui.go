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
		_, _ = io.WriteString(u.out, renderFrame(statusLine, morningPending, u.message, input))
		u.enabled = true
		return
	}
	_, _ = io.WriteString(u.out, renderFullFrame(statusLine, morningPending, u.message, input))
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
	return fmt.Sprintf(
		"status: %s morning reminder pending=%t\nmessage: %s\ncommand> %s",
		statusLine,
		morningPending,
		message,
		input,
	)
}

func renderFullFrame(statusLine string, morningPending bool, message string, input string) string {
	return "\x1b[3F\x1b[J" + renderFrame(statusLine, morningPending, message, input)
}
