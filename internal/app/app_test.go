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
	if !strings.Contains(line, "pomodoro 1/4") {
		t.Fatalf("expected pomodoro label, got %s", line)
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
