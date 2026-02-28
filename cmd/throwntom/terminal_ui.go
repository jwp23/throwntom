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
	u.mu.Lock()
	defer u.mu.Unlock()
	if !u.enabled {
		_, _ = io.WriteString(u.out, renderFrame(statusLine, morningPending, u.message, ""))
		u.enabled = true
		return
	}
	_, _ = io.WriteString(u.out, renderInPlaceFrame(statusLine, morningPending, u.message, ""))
	u.enabled = true
}

func (u *terminalUI) UpdateStatus(statusLine string, morningPending bool) {
	u.mu.Lock()
	defer u.mu.Unlock()
	if !u.enabled {
		return
	}
	_, _ = io.WriteString(u.out, renderInPlaceStatusLine(statusLine, morningPending, u.message))
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
		"status: %s morning_pending=%t\nmessage: %s\ncommand> %s",
		statusLine,
		morningPending,
		message,
		input,
	)
}

func renderInPlaceStatusLine(statusLine string, morningPending bool, message string) string {
	// Save cursor on command line, update status and message lines above, then restore.
	return fmt.Sprintf(
		"\x1b[s\x1b[2A\r\x1b[2Kstatus: %s morning_pending=%t\n\r\x1b[2Kmessage: %s\x1b[u",
		statusLine,
		morningPending,
		message,
	)
}

func renderInPlaceFrame(statusLine string, morningPending bool, message string, input string) string {
	// Called after Enter, when cursor moved below command line.
	return "\x1b[1A\r\x1b[2K\x1b[1A\r\x1b[2K\x1b[1A\r\x1b[2K" + renderFrame(statusLine, morningPending, message, input)
}
