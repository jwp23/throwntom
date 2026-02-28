package app

import (
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

type fakeNotifier struct {
	calls atomic.Int32
	err   error
}

func (f *fakeNotifier) PlaySound(string) error {
	f.calls.Add(1)
	return f.err
}

func TestStatusShowsAwaitingConfirm(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	a.Start()
	a.CompletePeriod()
	status := a.Status()
	if !strings.Contains(status, "awaiting confirmation") {
		t.Fatalf("unexpected status: %s", status)
	}
}

func TestConfirmStopsReminderLoop(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	a.Start()
	a.CompletePeriod()
	time.Sleep(70 * time.Millisecond)
	a.Confirm()
	got := n.calls.Load()
	time.Sleep(70 * time.Millisecond)
	if n.calls.Load() != got {
		t.Fatalf("expected reminder loop to stop after confirm")
	}
}

func TestCountdownFormatMMSS(t *testing.T) {
	got := formatRemaining(9*time.Minute + 5*time.Second)
	if got != "09:05" {
		t.Fatalf("expected 09:05, got %s", got)
	}
}

func TestStatusLineShowsPendingWhenAwaitingConfirm(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	a.Start()
	a.CompletePeriod()
	line := a.StatusLine()
	if !strings.Contains(line, "transition pending") {
		t.Fatalf("expected pending line, got %s", line)
	}
}

func TestStatusLineUsesPomodoroLabel(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	a.Start()
	line := a.StatusLine()
	if !strings.Contains(line, "pomodoros=0/4") {
		t.Fatalf("expected completed-only pomodoro progress, got %s", line)
	}
	if !strings.Contains(line, "today's pomodoros=0") {
		t.Fatalf("expected day total count in status line, got %s", line)
	}
	a.CompletePeriod()
	line = a.StatusLine()
	if !strings.Contains(line, "pomodoros=1/4") {
		t.Fatalf("expected done pomodoro progress after completion, got %s", line)
	}
}

func TestStatusLineShowsFullCycleAtLongBreakBoundary(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	a.Start()

	for i := 0; i < 3; i++ {
		a.CompletePeriod()
		a.Confirm()
		a.CompletePeriod()
		a.Confirm()
	}

	a.CompletePeriod()
	awaiting := a.StatusLine()
	if !strings.Contains(awaiting, "awaiting-confirm") {
		t.Fatalf("expected awaiting-confirm boundary state, got %s", awaiting)
	}
	if !strings.Contains(awaiting, "pomodoros=4/4") {
		t.Fatalf("expected full-cycle progress at boundary, got %s", awaiting)
	}

	a.Confirm()
	longBreak := a.StatusLine()
	if !strings.Contains(longBreak, "long-break") {
		t.Fatalf("expected long-break after confirming boundary transition, got %s", longBreak)
	}
	if !strings.Contains(longBreak, "pomodoros=4/4") {
		t.Fatalf("expected full-cycle progress during long break, got %s", longBreak)
	}
}

func TestPauseAndResume(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	a.Start()
	a.Pause()
	if got := a.Status(); got != "paused" {
		t.Fatalf("expected paused, got %s", got)
	}
	a.Resume()
	if got := a.Status(); got != "pomodoro" {
		t.Fatalf("expected pomodoro after resume, got %s", got)
	}
}

func TestStopResetsToIdle(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	a.Start()
	a.Stop()
	if got := a.Status(); got != "idle" {
		t.Fatalf("expected idle, got %s", got)
	}
	line := a.StatusLine()
	if !strings.Contains(line, "idle | 00:00") {
		t.Fatalf("expected idle countdown reset, got %s", line)
	}
}
