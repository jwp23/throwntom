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
}

func newTerminalUI(out io.Writer) *terminalUI {
	return &terminalUI{out: out}
}

func (u *terminalUI) ShowFrame(statusLine string, morningPending bool) {
	u.mu.Lock()
	defer u.mu.Unlock()
	_, _ = io.WriteString(u.out, renderFrame(statusLine, morningPending, ""))
	u.enabled = true
}

func (u *terminalUI) UpdateStatus(statusLine string, morningPending bool) {
	u.mu.Lock()
	defer u.mu.Unlock()
	if !u.enabled {
		return
	}
	_, _ = io.WriteString(u.out, renderInPlaceStatusLine(statusLine, morningPending))
}

func (u *terminalUI) Println(msg string) {
	u.mu.Lock()
	defer u.mu.Unlock()
	if u.enabled {
		_, _ = io.WriteString(u.out, "\n")
	}
	_, _ = io.WriteString(u.out, msg)
	_, _ = io.WriteString(u.out, "\n")
	u.enabled = false
}

func renderFrame(statusLine string, morningPending bool, input string) string {
	return fmt.Sprintf("status: %s morning_pending=%t\ncommand> %s", statusLine, morningPending, input)
}

func renderInPlaceStatusLine(statusLine string, morningPending bool) string {
	// Save cursor on command line, update status line above, then restore.
	return fmt.Sprintf("\x1b[s\x1b[1A\r\x1b[2Kstatus: %s morning_pending=%t\x1b[u", statusLine, morningPending)
}
