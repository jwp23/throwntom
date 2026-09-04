package analytics

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/eventlog"
)

// A meeting is credited work, so the pomodoros it earned belong in the stats
// beside the ones that were worked at the timer. One meeting logs one event
// carrying the credit it earned, rather than a run of completions that would
// claim pomodoros nobody sat.

func TestAMeetingCreditsItsPomodorosToTheStats(t *testing.T) {
	now := time.Date(2026, 9, 4, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 9, 4, 10, 0, 0, 0, time.Local)),
		makeEventWithData("meeting_completed", time.Date(2026, 9, 4, 11, 0, 0, 0, time.Local),
			map[string]any{"pomodoros": float64(2), "minutes": float64(60)}),
	}

	dash := Compute(events, now)

	if dash.Today.Pomodoros != 3 {
		t.Fatalf("today's pomodoros is %d, want 3", dash.Today.Pomodoros)
	}
	if dash.AllTime.Pomodoros != 3 {
		t.Fatalf("all-time pomodoros is %d, want 3", dash.AllTime.Pomodoros)
	}
}

// The minutes spent in a meeting are focused minutes: the user was working,
// just not at the timer.
func TestAMeetingCreditsItsMinutesAsFocusTime(t *testing.T) {
	now := time.Date(2026, 9, 4, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEventWithData("meeting_completed", time.Date(2026, 9, 4, 11, 0, 0, 0, time.Local),
			map[string]any{"pomodoros": float64(2), "minutes": float64(60)}),
	}

	dash := Compute(events, now)

	if dash.Today.FocusMinutes != 60 {
		t.Fatalf("today's focus minutes is %d, want 60", dash.Today.FocusMinutes)
	}
}

// A meeting too short to credit a pomodoro still logs, and still must not
// invent one.
func TestAMeetingThatCreditedNothingAddsNoPomodoro(t *testing.T) {
	now := time.Date(2026, 9, 4, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEventWithData("meeting_completed", time.Date(2026, 9, 4, 11, 0, 0, 0, time.Local),
			map[string]any{"pomodoros": float64(0), "minutes": float64(5)}),
	}

	dash := Compute(events, now)

	if dash.Today.Pomodoros != 0 {
		t.Fatalf("today's pomodoros is %d, want 0", dash.Today.Pomodoros)
	}
	if dash.Today.FocusMinutes != 5 {
		t.Fatalf("today's focus minutes is %d, want 5", dash.Today.FocusMinutes)
	}
}

// A meeting ends whatever pomodoro was open, so the time it took must not be
// charged to the next completion as if the user had been at the timer for it.
func TestAMeetingClosesTheOpenPomodoro(t *testing.T) {
	now := time.Date(2026, 9, 4, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_started", time.Date(2026, 9, 4, 9, 0, 0, 0, time.Local)),
		makeEventWithData("meeting_completed", time.Date(2026, 9, 4, 10, 0, 0, 0, time.Local),
			map[string]any{"pomodoros": float64(2), "minutes": float64(60)}),
		makeEvent("pomodoro_completed", time.Date(2026, 9, 4, 11, 0, 0, 0, time.Local)),
	}

	dash := Compute(events, now)

	// 60 from the meeting itself, and nothing from the hour before the
	// completion that followed it.
	if dash.Today.FocusMinutes != 60 {
		t.Fatalf("today's focus minutes is %d, want 60", dash.Today.FocusMinutes)
	}
}

// A malformed or truncated event must not crash the dashboard or invent
// credit; the log is read back from disk and cannot be assumed well-formed.
func TestAMeetingEventWithoutItsCreditIsHarmless(t *testing.T) {
	now := time.Date(2026, 9, 4, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("meeting_completed", time.Date(2026, 9, 4, 11, 0, 0, 0, time.Local)),
		makeEventWithData("meeting_completed", time.Date(2026, 9, 4, 12, 0, 0, 0, time.Local),
			map[string]any{"pomodoros": "two"}),
	}

	dash := Compute(events, now)

	if dash.Today.Pomodoros != 0 {
		t.Fatalf("today's pomodoros is %d, want 0", dash.Today.Pomodoros)
	}
	if dash.Today.FocusMinutes != 0 {
		t.Fatalf("today's focus minutes is %d, want 0", dash.Today.FocusMinutes)
	}
}
