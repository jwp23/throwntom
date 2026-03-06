package app

import (
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v2/internal/engine"
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

func TestStartNewCycleResetsCycleProgressButPreservesDailyTotal(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	a.Start()
	a.CompletePeriod()
	if !strings.Contains(a.StatusLine(), "today's pomodoros=1") {
		t.Fatalf("expected daily total before reset, got %s", a.StatusLine())
	}

	a.StartNewCycle()
	line := a.StatusLine()
	if !strings.Contains(line, "pomodoro") {
		t.Fatalf("expected pomodoro state after new cycle, got %s", line)
	}
	if !strings.Contains(line, "pomodoros=0/4") {
		t.Fatalf("expected cycle progress reset, got %s", line)
	}
	if !strings.Contains(line, "today's pomodoros=1") {
		t.Fatalf("expected daily total preserved, got %s", line)
	}
}

func TestRestoreWorkWithTimeRemaining(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	snap := Snapshot{
		Engine: engine.Snapshot{
			State:          engine.Work,
			LastPhase:      engine.Work,
			WorkSessions:   0,
			CompletedToday: 2,
			WorkDayStarted: true,
		},
		PhaseEndAt: time.Now().Add(10 * time.Minute),
	}
	if err := a.Restore(snap); err != nil {
		t.Fatalf("Restore: %v", err)
	}
	if got := a.Status(); got != "pomodoro" {
		t.Fatalf("expected pomodoro, got %s", got)
	}
	line := a.StatusLine()
	if !strings.Contains(line, "today's pomodoros=2") {
		t.Fatalf("expected completedToday=2, got %s", line)
	}
}

func TestRestoreWorkExpiredTransitionsToAwaitingConfirm(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	snap := Snapshot{
		Engine: engine.Snapshot{
			State:          engine.Work,
			LastPhase:      engine.Work,
			WorkSessions:   0,
			CompletedToday: 0,
			WorkDayStarted: true,
		},
		PhaseEndAt: time.Now().Add(-1 * time.Second),
	}
	if err := a.Restore(snap); err != nil {
		t.Fatalf("Restore: %v", err)
	}
	if got := a.Status(); got != "awaiting confirmation" {
		t.Fatalf("expected awaiting confirmation, got %s", got)
	}
}

func TestRestorePausedPreservesRemaining(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	snap := Snapshot{
		Engine: engine.Snapshot{
			State:      engine.Paused,
			LastPhase:  engine.Work,
			PausedFrom: engine.Work,
		},
		PausedRemaining: 12 * time.Minute,
	}
	if err := a.Restore(snap); err != nil {
		t.Fatalf("Restore: %v", err)
	}
	if got := a.Status(); got != "paused" {
		t.Fatalf("expected paused, got %s", got)
	}
	a.Resume()
	if got := a.Status(); got != "pomodoro" {
		t.Fatalf("expected pomodoro after resume, got %s", got)
	}
}

func TestRestoreAwaitingConfirmStartsReminder(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	snap := Snapshot{
		Engine: engine.Snapshot{
			State:     engine.AwaitingConfirm,
			LastPhase: engine.Work,
		},
	}
	if err := a.Restore(snap); err != nil {
		t.Fatalf("Restore: %v", err)
	}
	if got := a.Status(); got != "awaiting confirmation" {
		t.Fatalf("expected awaiting confirmation, got %s", got)
	}
	time.Sleep(50 * time.Millisecond)
	if n.calls.Load() == 0 {
		t.Fatal("expected reminder to fire after restoring AwaitingConfirm")
	}
	a.Stop()
}

func TestRestoreIdleIsClean(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	snap := Snapshot{
		Engine: engine.Snapshot{
			State:          engine.Idle,
			CompletedToday: 5,
			WorkDayStarted: true,
		},
	}
	if err := a.Restore(snap); err != nil {
		t.Fatalf("Restore: %v", err)
	}
	if got := a.Status(); got != "idle" {
		t.Fatalf("expected idle, got %s", got)
	}
	line := a.StatusLine()
	if !strings.Contains(line, "today's pomodoros=5") {
		t.Fatalf("expected completedToday=5 preserved, got %s", line)
	}
}

func TestSnapshotRestoreRoundTrip(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	a.Start()
	a.CompletePeriod()
	a.Confirm()

	snap := a.Snapshot()
	a2 := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	if err := a2.Restore(snap); err != nil {
		t.Fatalf("Restore: %v", err)
	}
	if got := a2.Status(); got != "short-break" {
		t.Fatalf("expected short-break after restore, got %s", got)
	}
	line := a2.StatusLine()
	if !strings.Contains(line, "today's pomodoros=1") {
		t.Fatalf("expected completedToday=1, got %s", line)
	}
	a2.Stop()
}
