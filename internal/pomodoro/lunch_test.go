package pomodoro

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

func TestStartLunchRunsForTheLunchDuration(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)

	a.StartLunch()

	if got := a.State(); got != engine.Lunch {
		t.Fatalf("state is %s, want lunch", got)
	}
	if remaining := a.Snapshot().PhaseEndAt.Sub(clock.Now()); remaining != 60*time.Minute {
		t.Fatalf("lunch has %s left, want 60m", remaining)
	}
}

func TestLunchEndsOnItsOwnDeadline(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 12, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.StartLunch()

	clock.Advance(60 * time.Minute)

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("state is %s, want awaiting_confirm", got)
	}
	next, duration := a.NextStage()
	if next != engine.Work || duration != 25*time.Minute {
		t.Fatalf("next stage is %s for %s, want work for 25m", next, duration)
	}
}

// StartLunch reports the state it acted from, the way Stop and StartNewCycle
// do, so the caller can credit a completion it displaced without a second,
// racy read.
func TestStartLunchReportsTheStateItDisplaced(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.Start()
	clock.Advance(25 * time.Minute)

	before := a.StartLunch()

	if before.State != engine.AwaitingConfirm || before.LastPhase != engine.Work {
		t.Fatalf("reported %s/%s, want awaiting_confirm/work", before.State, before.LastPhase)
	}
}

// A lunch already under way is measured against the reloaded length, the same
// rule every other running phase gets (ADR-008).
func TestApplyDurationsRederivesARunningLunch(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 12, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.StartLunch()
	clock.Advance(20 * time.Minute)

	d := minutes(25, 5, 15, 4)
	d.LunchMinutes = 45
	a.ApplyDurations(d)

	if remaining := a.Snapshot().PhaseEndAt.Sub(clock.Now()); remaining != 25*time.Minute {
		t.Fatalf("lunch has %s left of the new 45m, want 25m", remaining)
	}
}

func TestApplyDurationsShorterThanTheLunchServedEndsIt(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 12, 0, 0, 0, time.UTC))
	a.setClock(clock)
	a.StartLunch()
	clock.Advance(20 * time.Minute)

	d := minutes(25, 5, 15, 4)
	d.LunchMinutes = 15
	a.ApplyDurations(d)

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("state is %s, want awaiting_confirm", got)
	}
}

func TestStatusLineNamesLunch(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	clock := newFakeClock(time.Date(2026, 8, 29, 12, 0, 0, 0, time.UTC))
	a.setClock(clock)

	a.StartLunch()

	if want := "Lunch  60:00  Today: 0  Cycle: 0/4"; a.StatusLine() != want {
		t.Fatalf("status line is %q, want %q", a.StatusLine(), want)
	}
}
