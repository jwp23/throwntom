package main

import (
	"bytes"
	"strings"
	"testing"
	"time"
)

func TestInteractiveLoopTickRedrawKeepsPromptBuffer(t *testing.T) {
	var out bytes.Buffer
	ui := newTerminalUI(&out)

	keys := make(chan keyEvent, 8)
	ticks := make(chan time.Time, 1)
	resizes := make(chan struct{}, 1)
	readErr := make(chan error, 1)

	var submitted string
	cb := interactiveCallbacks{
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00", false
		},
		Execute: func(command string) (daemonControlResponse, error) {
			submitted = command
			return daemonControlResponse{
				StatusLine:     "idle | 00:00",
				MorningPending: false,
				Exit:           true,
			}, nil
		},
	}

	done := make(chan error, 1)
	go func() {
		done <- runInteractiveEventLoop(ui, cb, keys, ticks, resizes, readErr)
	}()

	keys <- keyEvent{kind: keyPrintable, r: 's'}
	keys <- keyEvent{kind: keyPrintable, r: 't'}
	ticks <- time.Now()
	keys <- keyEvent{kind: keyEnter}

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("loop returned error: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for interactive loop to exit")
	}

	if submitted != "st" {
		t.Fatalf("expected submitted command %q, got %q", "st", submitted)
	}
	if !strings.Contains(out.String(), "command> st") {
		t.Fatalf("expected prompt buffer to remain visible during tick redraw, got output %q", out.String())
	}
}

func TestInteractiveLoopResizeRedrawKeepsPromptVisible(t *testing.T) {
	var out bytes.Buffer
	ui := newTerminalUI(&out)

	keys := make(chan keyEvent, 8)
	ticks := make(chan time.Time, 1)
	resizes := make(chan struct{}, 1)
	readErr := make(chan error, 1)

	var submitted string
	cb := interactiveCallbacks{
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00", false
		},
		Execute: func(command string) (daemonControlResponse, error) {
			submitted = command
			return daemonControlResponse{
				StatusLine:     "idle | 00:00",
				MorningPending: false,
				Exit:           true,
			}, nil
		},
	}

	done := make(chan error, 1)
	go func() {
		done <- runInteractiveEventLoop(ui, cb, keys, ticks, resizes, readErr)
	}()

	keys <- keyEvent{kind: keyPrintable, r: 's'}
	keys <- keyEvent{kind: keyPrintable, r: 't'}
	resizes <- struct{}{}
	keys <- keyEvent{kind: keyEnter}

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("loop returned error: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for interactive loop to exit")
	}

	if submitted != "st" {
		t.Fatalf("expected submitted command %q, got %q", "st", submitted)
	}
	if !strings.Contains(out.String(), "command> st") {
		t.Fatalf("expected prompt to remain visible after resize redraw, got output %q", out.String())
	}
}

func TestInteractiveLoopEnterExecutesCommandAndClearsInput(t *testing.T) {
	var out bytes.Buffer
	ui := newTerminalUI(&out)

	keys := make(chan keyEvent, 16)
	ticks := make(chan time.Time, 1)
	resizes := make(chan struct{}, 1)
	readErr := make(chan error, 1)

	var submitted string
	cb := interactiveCallbacks{
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00", false
		},
		Execute: func(command string) (daemonControlResponse, error) {
			submitted = command
			return daemonControlResponse{
				StatusLine:     "idle | 00:00",
				MorningPending: false,
				Message:        "ok",
				Exit:           true,
			}, nil
		},
	}

	done := make(chan error, 1)
	go func() {
		done <- runInteractiveEventLoop(ui, cb, keys, ticks, resizes, readErr)
	}()

	keys <- keyEvent{kind: keyPrintable, r: 's'}
	keys <- keyEvent{kind: keyPrintable, r: 't'}
	keys <- keyEvent{kind: keyPrintable, r: 'a'}
	keys <- keyEvent{kind: keyPrintable, r: 't'}
	keys <- keyEvent{kind: keyPrintable, r: 'u'}
	keys <- keyEvent{kind: keyPrintable, r: 's'}
	keys <- keyEvent{kind: keyEnter}

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("loop returned error: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for interactive loop to exit")
	}

	if submitted != "status" {
		t.Fatalf("expected submitted command %q, got %q", "status", submitted)
	}
	if !strings.Contains(out.String(), "command> status") {
		t.Fatalf("expected typed command to be rendered before submission, got output %q", out.String())
	}
	if !strings.Contains(out.String(), "message: ok\ncommand> ") {
		t.Fatalf("expected prompt to clear after enter, got output %q", out.String())
	}
}

func TestInteractiveLoopCtrlCExitsWithoutExecutingCommand(t *testing.T) {
	var out bytes.Buffer
	ui := newTerminalUI(&out)

	keys := make(chan keyEvent, 4)
	ticks := make(chan time.Time, 1)
	resizes := make(chan struct{}, 1)
	readErr := make(chan error, 1)

	executed := false
	cb := interactiveCallbacks{
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00", false
		},
		Execute: func(command string) (daemonControlResponse, error) {
			executed = true
			return daemonControlResponse{}, nil
		},
	}

	done := make(chan error, 1)
	go func() {
		done <- runInteractiveEventLoop(ui, cb, keys, ticks, resizes, readErr)
	}()

	keys <- keyEvent{kind: keyInterrupt}

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("loop returned error: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for interactive loop to exit")
	}

	if executed {
		t.Fatal("expected ctrl-c exit to avoid executing command callback")
	}
}
