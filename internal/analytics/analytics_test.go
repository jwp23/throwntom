package analytics

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/eventlog"
)

func makeEvent(typ string, ts time.Time) eventlog.Event {
	return eventlog.Event{Type: typ, Timestamp: ts}
}

func makeEventWithData(typ string, ts time.Time, data map[string]any) eventlog.Event {
	return eventlog.Event{Type: typ, Timestamp: ts, Data: data}
}

func TestComputeEmpty(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	dash := Compute(nil, now)
	if dash.Today.Pomodoros != 0 {
		t.Fatalf("expected 0 today pomodoros, got %d", dash.Today.Pomodoros)
	}
	if dash.AllTime.Pomodoros != 0 {
		t.Fatalf("expected 0 all-time pomodoros, got %d", dash.AllTime.Pomodoros)
	}
}

func TestComputeToday(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 11, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 18, 10, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Today.Pomodoros != 2 {
		t.Fatalf("expected 2 today pomodoros, got %d", dash.Today.Pomodoros)
	}
}

func TestComputeThisWeek(t *testing.T) {
	// 2026-03-19 is a Thursday. Week starts Monday 2026-03-16.
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 16, 10, 0, 0, 0, time.Local)), // Mon
		makeEvent("pomodoro_completed", time.Date(2026, 3, 17, 10, 0, 0, 0, time.Local)), // Tue
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)), // Thu
		makeEvent("pomodoro_completed", time.Date(2026, 3, 15, 10, 0, 0, 0, time.Local)), // Sun (prev week)
	}
	dash := Compute(events, now)
	if dash.ThisWeek.Pomodoros != 3 {
		t.Fatalf("expected 3 this-week pomodoros, got %d", dash.ThisWeek.Pomodoros)
	}
	if len(dash.ThisWeek.DailyCounts) == 0 {
		t.Fatal("expected non-empty DailyCounts for this week")
	}
}

func TestComputeThisMonth(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 1, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 10, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 2, 28, 10, 0, 0, 0, time.Local)), // prev month
	}
	dash := Compute(events, now)
	if dash.ThisMonth.Pomodoros != 3 {
		t.Fatalf("expected 3 this-month pomodoros, got %d", dash.ThisMonth.Pomodoros)
	}
}

func TestComputeAllTime(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 1, 15, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 2, 10, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.AllTime.Pomodoros != 3 {
		t.Fatalf("expected 3 all-time pomodoros, got %d", dash.AllTime.Pomodoros)
	}
}

func TestComputeFocusMinutes(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_started", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 25, 0, 0, time.Local)),
		makeEvent("pomodoro_started", time.Date(2026, 3, 19, 10, 30, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 55, 0, 0, time.Local)),
		// Unpaired start — should be excluded
		makeEvent("pomodoro_started", time.Date(2026, 3, 19, 11, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Today.FocusMinutes != 50 {
		t.Fatalf("expected 50 focus minutes today, got %d", dash.Today.FocusMinutes)
	}
}

// A stopped pomodoro is not focus time, and it must not leak into the next
// completion's duration either.
func TestStopClosesTheOpenPomodoro(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_started", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
		makeEvent("stopped", time.Date(2026, 3, 19, 10, 10, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 11, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Today.FocusMinutes != 0 {
		t.Fatalf("expected a stop to end the open pomodoro, got %d focus minutes", dash.Today.FocusMinutes)
	}
}

// A skipped pomodoro is not focus time either.
func TestSkipClosesTheOpenPomodoro(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_started", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
		makeEvent("skipped", time.Date(2026, 3, 19, 10, 10, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 11, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Today.FocusMinutes != 0 {
		t.Fatalf("expected a skip to end the open pomodoro, got %d focus minutes", dash.Today.FocusMinutes)
	}
}

func TestComputePausesSnoozes(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
		makeEvent("paused", time.Date(2026, 3, 19, 10, 5, 0, 0, time.Local)),
		makeEvent("paused", time.Date(2026, 3, 19, 10, 15, 0, 0, time.Local)),
		makeEventWithData("snoozed", time.Date(2026, 3, 19, 10, 20, 0, 0, time.Local), map[string]any{"duration_secs": 300}),
	}
	dash := Compute(events, now)
	if dash.Today.Pauses != 2 {
		t.Fatalf("expected 2 pauses today, got %d", dash.Today.Pauses)
	}
	if dash.Today.Snoozes != 1 {
		t.Fatalf("expected 1 snooze today, got %d", dash.Today.Snoozes)
	}
}

// TestPomDaysCountsEachCompletionIndependently pins the increment (not
// decrement) that tallies a day's completions: two completions on the same
// day must show as 2 in that day's DailyCounts entry, not 0.
func TestPomDaysCountsEachCompletionIndependently(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 11, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	var got int
	for _, dc := range dash.ThisWeek.DailyCounts {
		if dc.Date.Equal(startOfDay(now)) {
			got = dc.Count
		}
	}
	if got != 2 {
		t.Fatalf("today's DailyCounts entry is %d, want 2", got)
	}
}

// TestBestHourTieKeepsTheEarlierHour pins the strict ">" in computePatterns:
// on a tie, the first hour reached (the lowest hour number, since the loop
// runs 0..23) must stay best rather than being overwritten by a later hour
// with the same count.
func TestBestHourTieKeepsTheEarlierHour(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 17, 9, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 18, 15, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Patterns.BestHour != 9 {
		t.Fatalf("expected the earlier tied hour 9, got %d", dash.Patterns.BestHour)
	}
}

// TestAvgByWeekdayIncludesSaturday pins the loop bound "wd <= time.Saturday":
// a day this loop skips never gets an AvgByWeekday entry at all.
func TestAvgByWeekdayIncludesSaturday(t *testing.T) {
	now := time.Date(2026, 3, 21, 14, 0, 0, 0, time.Local) // a Saturday
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 21, 10, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Patterns.AvgByWeekday[time.Saturday] != 1.0 {
		t.Fatalf("expected Saturday avg 1.0, got %.1f", dash.Patterns.AvgByWeekday[time.Saturday])
	}
}

// TestAvgByWeekdayWithNoEventsIsZeroNotNaN pins the "days > 0" guard: a
// weekday with no completions must show 0, not the 0/0 NaN a boundary
// mutant here would let through.
func TestAvgByWeekdayWithNoEventsIsZeroNotNaN(t *testing.T) {
	now := time.Date(2026, 3, 16, 14, 0, 0, 0, time.Local) // a Monday
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 16, 10, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if avg := dash.Patterns.AvgByWeekday[time.Friday]; avg != 0 {
		t.Fatalf("expected Friday avg 0 (no data), got %v", avg)
	}
}

// TestBestDayTieKeepsTheEarlierDay pins the strict ">" in computePatterns:
// on a tie, the first weekday reached (the loop runs Sunday..Saturday) must
// stay best rather than being overwritten by a later day with the same
// average.
func TestBestDayTieKeepsTheEarlierDay(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		// Sunday 2026-03-15: 1 pomodoro.
		makeEvent("pomodoro_completed", time.Date(2026, 3, 15, 10, 0, 0, 0, time.Local)),
		// Monday 2026-03-16: 1 pomodoro. Same average (1.0), later in the loop.
		makeEvent("pomodoro_completed", time.Date(2026, 3, 16, 10, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Patterns.BestDay != time.Sunday {
		t.Fatalf("expected the earlier tied day Sunday, got %v", dash.Patterns.BestDay)
	}
}

// TestSortDatesReversesFullyDescendingInput exercises the insertion sort's
// inner loop directly, deterministically: Streaks' own tests build sorted's
// input from map iteration, whose order Go randomizes, so whether the
// swap loop actually runs more than once depends on luck rather than the
// test. A fully-descending slice forces every element to travel the whole
// way to the front.
func TestSortDatesReversesFullyDescendingInput(t *testing.T) {
	d := func(day int) time.Time { return time.Date(2026, 3, day, 0, 0, 0, 0, time.UTC) }
	dates := []time.Time{d(5), d(4), d(3), d(2), d(1)}
	sortDates(dates)
	for i, want := range []int{1, 2, 3, 4, 5} {
		if dates[i].Day() != want {
			t.Fatalf("dates[%d].Day() = %d, want %d (dates = %v)", i, dates[i].Day(), want, dates)
		}
	}
}

func TestStreakCurrent(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 17, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 18, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Streaks.Current != 3 {
		t.Fatalf("expected current streak 3, got %d", dash.Streaks.Current)
	}
}

func TestStreakLongest(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 10, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 11, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 12, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 13, 10, 0, 0, 0, time.Local)),
		// gap on 14th
		makeEvent("pomodoro_completed", time.Date(2026, 3, 18, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Streaks.Longest != 4 {
		t.Fatalf("expected longest streak 4, got %d", dash.Streaks.Longest)
	}
	if dash.Streaks.Current != 2 {
		t.Fatalf("expected current streak 2, got %d", dash.Streaks.Current)
	}
}

func TestStreakGapResets(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 17, 10, 0, 0, 0, time.Local)),
		// gap on 18th
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Streaks.Current != 1 {
		t.Fatalf("expected current streak 1 (gap resets), got %d", dash.Streaks.Current)
	}
}

func TestStreakTodayOnly(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Streaks.Current != 1 {
		t.Fatalf("expected current streak 1, got %d", dash.Streaks.Current)
	}
	if dash.Streaks.Longest != 1 {
		t.Fatalf("expected longest streak 1, got %d", dash.Streaks.Longest)
	}
}

func TestBestDay(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		// Monday x2
		makeEvent("pomodoro_completed", time.Date(2026, 3, 16, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 16, 11, 0, 0, 0, time.Local)),
		// Tuesday x3
		makeEvent("pomodoro_completed", time.Date(2026, 3, 17, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 17, 11, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 17, 12, 0, 0, 0, time.Local)),
		// Thursday x1
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Patterns.BestDay != time.Tuesday {
		t.Fatalf("expected best day Tuesday, got %v", dash.Patterns.BestDay)
	}
}

func TestBestHour(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 17, 10, 5, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 18, 10, 30, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 55, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Patterns.BestHour != 10 {
		t.Fatalf("expected best hour 10, got %d", dash.Patterns.BestHour)
	}
}

func TestAvgByWeekday(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		// Two Mondays with 2 and 4 pomodoros
		makeEvent("pomodoro_completed", time.Date(2026, 3, 9, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 9, 11, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 16, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 16, 11, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 16, 12, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 16, 13, 0, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	avg := dash.Patterns.AvgByWeekday[time.Monday]
	if avg != 3.0 {
		t.Fatalf("expected avg Monday 3.0, got %.1f", avg)
	}
}

func TestSnoozeRate(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 11, 0, 0, 0, time.Local)),
		makeEventWithData("snoozed", time.Date(2026, 3, 19, 10, 30, 0, 0, time.Local), nil),
	}
	dash := Compute(events, now)
	if dash.Patterns.SnoozeRate != 0.5 {
		t.Fatalf("expected snooze rate 0.5, got %f", dash.Patterns.SnoozeRate)
	}
}

func TestPauseRate(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 11, 0, 0, 0, time.Local)),
		makeEvent("pomodoro_completed", time.Date(2026, 3, 19, 12, 0, 0, 0, time.Local)),
		makeEvent("paused", time.Date(2026, 3, 19, 10, 5, 0, 0, time.Local)),
		makeEvent("paused", time.Date(2026, 3, 19, 11, 5, 0, 0, time.Local)),
		makeEvent("paused", time.Date(2026, 3, 19, 12, 5, 0, 0, time.Local)),
	}
	dash := Compute(events, now)
	if dash.Patterns.PauseRate != 1.0 {
		t.Fatalf("expected pause rate 1.0, got %f", dash.Patterns.PauseRate)
	}
}

func TestNoDivisionByZero(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	events := []eventlog.Event{
		makeEvent("paused", time.Date(2026, 3, 19, 10, 0, 0, 0, time.Local)),
		makeEventWithData("snoozed", time.Date(2026, 3, 19, 10, 5, 0, 0, time.Local), nil),
	}
	dash := Compute(events, now)
	if dash.Patterns.SnoozeRate != 0 {
		t.Fatalf("expected snooze rate 0 with no pomodoros, got %f", dash.Patterns.SnoozeRate)
	}
	if dash.Patterns.PauseRate != 0 {
		t.Fatalf("expected pause rate 0 with no pomodoros, got %f", dash.Patterns.PauseRate)
	}
}
