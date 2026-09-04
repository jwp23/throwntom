package pomodoro

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// A meeting runs for a length the user picks at the moment they start it,
// rather than one the config holds, and credits the time actually spent in it
// whichever way it ends.

func TestStartMeetingRunsForTheLengthItWasGiven(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 9, 4, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)

	a.StartMeeting(30 * time.Minute)

	if got := a.State(); got != engine.Meeting {
		t.Fatalf("state is %s, want meeting", got)
	}
	if remaining := a.Snapshot().PhaseEndAt.Sub(clock.Now()); remaining != 30*time.Minute {
		t.Fatalf("meeting has %s left, want 30m", remaining)
	}
}

func TestMeetingEndsOnItsOwnDeadlineAndCredits(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 9, 4, 10, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.StartMeeting(60 * time.Minute)

	clock.Advance(60 * time.Minute)

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("state is %s, want awaiting_confirm", got)
	}
	if got := a.Snapshot().Engine.CompletedToday; got != 2 {
		t.Fatalf("completed today is %d, want 2", got)
	}
	next, duration := a.NextStage()
	if next != engine.Work || duration != 25*time.Minute {
		t.Fatalf("next stage is %s for %s, want work for 25m", next, duration)
	}
}

// Ending a meeting early credits the time that was spent in it, which is what
// separates it from skipping a pomodoro: the meeting happened.
func TestEndingAMeetingEarlyCreditsTheTimeSpent(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 9, 4, 10, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.StartMeeting(60 * time.Minute)

	clock.Advance(40 * time.Minute)
	ended, ok := a.Skip()

	if !ok || ended != engine.Meeting {
		t.Fatalf("skip reported %s/%v, want meeting/true", ended, ok)
	}
	if got := a.Snapshot().Engine.CompletedToday; got != 2 {
		t.Fatalf("completed today is %d, want 2 -- 40 minutes rounds to 2 pomodoros", got)
	}
	if a.Snapshot().Engine.Skipped {
		t.Fatal("an ended meeting is marked skipped, so its credit will not be logged")
	}
}

func TestEndingAMeetingTooEarlyToCreditStillEndsIt(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 9, 4, 10, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.StartMeeting(60 * time.Minute)

	clock.Advance(5 * time.Minute)
	a.Skip()

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("state is %s, want awaiting_confirm", got)
	}
	if got := a.Snapshot().Engine.CompletedToday; got != 0 {
		t.Fatalf("completed today is %d, want 0", got)
	}
}

// A pause stops the meeting's clock, so what it credits is the time spent in
// the meeting rather than the time on the wall.
func TestAPausedMeetingCreditsOnlyTheTimeSpentInIt(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 9, 4, 10, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.StartMeeting(60 * time.Minute)

	clock.Advance(30 * time.Minute)
	a.Pause()
	clock.Advance(2 * time.Hour)
	a.Resume()
	a.Skip()

	if got := a.Snapshot().Engine.CompletedToday; got != 1 {
		t.Fatalf("completed today is %d, want 1 -- only the 30 minutes in the meeting count", got)
	}
}

// A meeting that ran out while the daemon was down comes back finished, with
// the credit it earned, rather than as a phase that never ended.
func TestAMeetingThatExpiredDuringDowntimeComesBackCredited(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	start := time.Date(2026, 9, 4, 10, 0, 0, 0, time.UTC)
	clock := newFakeClock(start)
	a.setClock(clock)
	a.StartMeeting(60 * time.Minute)
	saved := a.Snapshot()

	restored := New(minutes(25, 5, 15, 4))
	restoredClock := newFakeClock(start.Add(90 * time.Minute))
	restored.setClock(restoredClock)
	if err := restored.Restore(saved, restoredClock.Now()); err != nil {
		t.Fatalf("restore: %v", err)
	}

	if got := restored.State(); got != engine.AwaitingConfirm {
		t.Fatalf("state is %s, want awaiting_confirm", got)
	}
	if got := restored.Snapshot().Engine.CompletedToday; got != 2 {
		t.Fatalf("completed today is %d, want 2 -- the full 60-minute meeting", got)
	}
}

// A meeting in flight survives a restart with the length it was given, which
// no config field holds and only the session can carry.
func TestARunningMeetingKeepsItsLengthAcrossARestart(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	start := time.Date(2026, 9, 4, 10, 0, 0, 0, time.UTC)
	clock := newFakeClock(start)
	a.setClock(clock)
	a.StartMeeting(90 * time.Minute)
	clock.Advance(10 * time.Minute)
	saved := a.Snapshot()

	restored := New(minutes(25, 5, 15, 4))
	restoredClock := newFakeClock(start.Add(10 * time.Minute))
	restored.setClock(restoredClock)
	if err := restored.Restore(saved, restoredClock.Now()); err != nil {
		t.Fatalf("restore: %v", err)
	}

	if got := restored.State(); got != engine.Meeting {
		t.Fatalf("state is %s, want meeting", got)
	}
	remaining := restored.Snapshot().PhaseEndAt.Sub(restoredClock.Now())
	if remaining != 80*time.Minute {
		t.Fatalf("meeting has %s left, want 80m", remaining)
	}
}

// A config reload re-derives every running phase against its new length. A
// meeting's length came from the user, not the config, so a reload leaves it
// exactly where it was.
func TestAConfigReloadDoesNotChangeARunningMeeting(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 9, 4, 10, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.StartMeeting(45 * time.Minute)
	clock.Advance(10 * time.Minute)

	a.ApplyDurations(minutes(50, 10, 30, 4))

	if got := a.State(); got != engine.Meeting {
		t.Fatalf("state is %s, want meeting", got)
	}
	if remaining := a.Snapshot().PhaseEndAt.Sub(clock.Now()); remaining != 35*time.Minute {
		t.Fatalf("meeting has %s left, want 35m", remaining)
	}
}

// The credit is measured against the pomodoro length in force when the meeting
// ends, the way every other duration question is settled (ADR-008).
func TestMeetingCreditUsesThePomodoroLengthInForceWhenItEnds(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 9, 4, 10, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.StartMeeting(60 * time.Minute)

	// 60 minutes is 2.4 pomodoros of 25 minutes but only 1.2 of 50, so the
	// length in force is what the credit turns on.
	a.ApplyDurations(minutes(50, 5, 15, 4))
	clock.Advance(60 * time.Minute)

	if got := a.Snapshot().Engine.CompletedToday; got != 1 {
		t.Fatalf("completed today is %d, want 1 -- 60 minutes of 50-minute pomodoros", got)
	}
}

func TestTheStatusLineNamesAMeeting(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 9, 4, 10, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.StartMeeting(30 * time.Minute)

	if got := a.StatusLine(); got[:7] != "Meeting" {
		t.Fatalf("status line is %q, want it to start with Meeting", got)
	}
}

// StartMeeting reports the state it acted from, the way StartLunch and Stop
// do, so the caller can credit a completion it displaced without a second,
// racy read.
func TestStartMeetingReportsTheStateItDisplaced(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 9, 4, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(25 * time.Minute)

	before := a.StartMeeting(30 * time.Minute)

	if before.State != engine.AwaitingConfirm || before.LastPhase != engine.Work {
		t.Fatalf("reported %s/%s, want awaiting_confirm/work", before.State, before.LastPhase)
	}
}
