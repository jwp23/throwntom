package workday

import (
	"errors"
	"testing"
	"time"
	// The DST tests need a named zone, and a machine without the system zone
	// database would otherwise skip the semantics they exist to pin.
	_ "time/tzdata"
)

const fourAM = "04:00"

func mustParse(t *testing.T, hhmm string) Start {
	t.Helper()
	s, err := ParseStart(hhmm)
	if err != nil {
		t.Fatalf("ParseStart(%q): %v", hhmm, err)
	}
	return s
}

func TestParseStartAcceptsHHMM(t *testing.T) {
	for _, hhmm := range []string{"00:00", fourAM, "09:15", "23:59"} {
		if _, err := ParseStart(hhmm); err != nil {
			t.Errorf("ParseStart(%q): %v", hhmm, err)
		}
	}
}

func TestParseStartRejectsAnythingElse(t *testing.T) {
	for _, hhmm := range []string{"", "4:00", "04:0", "0400", "24:00", "04:60", "-1:00", "+4:00", "aa:bb", "04:00:00"} {
		if _, err := ParseStart(hhmm); err == nil {
			t.Errorf("ParseStart(%q) was accepted, want an error", hhmm)
		}
	}
}

// One parser reads every HH:MM the config writes — the day start, and the
// schedule times through internal/config and internal/scheduler — so the
// three of them cannot disagree about what a time of day looks like.
func TestParseHHMMReadsTheTimeOfDay(t *testing.T) {
	for _, tc := range []struct {
		hhmm         string
		hour, minute int
	}{
		{"00:00", 0, 0},
		{fourAM, 4, 0},
		{"09:15", 9, 15},
		{"23:59", 23, 59},
	} {
		hour, minute, err := ParseHHMM(tc.hhmm)
		if err != nil {
			t.Errorf("ParseHHMM(%q): %v", tc.hhmm, err)
			continue
		}
		if hour != tc.hour || minute != tc.minute {
			t.Errorf("ParseHHMM(%q) = %d:%d, want %d:%d", tc.hhmm, hour, minute, tc.hour, tc.minute)
		}
	}
}

// The error says which of the two things went wrong, because a caller quotes
// it back at the user: a time that is not HH:MM at all is a different mistake
// from one whose hour is out of range.
func TestParseHHMMNamesTheProblem(t *testing.T) {
	for _, tc := range []struct {
		hhmm string
		want error
	}{
		{"aa:bb", errFormat},
		{"+4:00", errFormat},
		{"0400", errFormat},
		{"04:00:00", errFormat},
		{"24:00", errHour},
		{"04:60", errMinute},
	} {
		if _, _, err := ParseHHMM(tc.hhmm); !errors.Is(err, tc.want) {
			t.Errorf("ParseHHMM(%q) = %v, want %v", tc.hhmm, err, tc.want)
		}
	}
}

func TestMustParseStartPanicsOnAnInvalidStart(t *testing.T) {
	defer func() {
		if recover() == nil {
			t.Fatal("expected MustParseStart to panic on an invalid start")
		}
	}()
	MustParseStart("nope")
}

// A work day runs from the start hour to the next, so late evening and the
// small hours that follow it are one day and the boundary is the only place
// the day changes.
func TestSameWorkDay(t *testing.T) {
	local := func(y int, m time.Month, d, hour, minute int) time.Time {
		return time.Date(y, m, d, hour, minute, 0, 0, time.Local)
	}
	tests := []struct {
		name  string
		start string
		a, b  time.Time
		want  bool
	}{
		{"two moments in the working day", fourAM, local(2026, 3, 5, 9, 0), local(2026, 3, 5, 17, 0), true},
		{"an evening and the small hours after it", fourAM, local(2026, 3, 5, 22, 0), local(2026, 3, 6, 2, 0), true},
		{"either side of the start hour", fourAM, local(2026, 3, 6, 3, 59), local(2026, 3, 6, 4, 0), false},
		{"the first and last minute of one day", fourAM, local(2026, 3, 5, 4, 0), local(2026, 3, 6, 3, 59), true},
		{"midnight is not the boundary", fourAM, local(2026, 2, 28, 23, 59), local(2026, 3, 1, 0, 1), true},
		{"the same clock time a day apart", fourAM, local(2026, 3, 5, 12, 0), local(2026, 3, 6, 12, 0), false},
		{"the same date a year apart", fourAM, local(2025, 3, 5, 12, 0), local(2026, 3, 5, 12, 0), false},
		{"a midnight boundary still splits at midnight", "00:00", local(2026, 3, 5, 23, 59), local(2026, 3, 6, 0, 1), false},
		{"a midnight boundary keeps the calendar day whole", "00:00", local(2026, 3, 5, 0, 0), local(2026, 3, 5, 23, 59), true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			s := mustParse(t, tc.start)
			if got := s.Same(tc.a, tc.b); got != tc.want {
				t.Errorf("Same(%v, %v) = %v, want %v", tc.a, tc.b, got, tc.want)
			}
			if got := s.Same(tc.b, tc.a); got != tc.want {
				t.Errorf("Same is not symmetric: Same(%v, %v) = %v, want %v", tc.b, tc.a, got, tc.want)
			}
		})
	}
}

// The key names the day the work belongs to, which before the start hour is
// yesterday's date — across a month and a year boundary alike.
func TestKeyNamesTheWorkDayTheMomentBelongsTo(t *testing.T) {
	s := mustParse(t, fourAM)
	tests := []struct {
		now  time.Time
		want string
	}{
		{time.Date(2026, 3, 5, 22, 0, 0, 0, time.Local), "2026-03-05"},
		{time.Date(2026, 3, 6, 2, 0, 0, 0, time.Local), "2026-03-05"},
		{time.Date(2026, 3, 6, 4, 0, 0, 0, time.Local), "2026-03-06"},
		{time.Date(2026, 3, 1, 3, 59, 0, 0, time.Local), "2026-02-28"},
		{time.Date(2026, 1, 1, 1, 0, 0, 0, time.Local), "2025-12-31"},
	}
	for _, tc := range tests {
		if got := s.Key(tc.now); got != tc.want {
			t.Errorf("Key(%v) = %q, want %q", tc.now, got, tc.want)
		}
	}
}

// The boundary is a wall-clock time, so a day that gains or loses an hour to
// a DST transition is simply an hour longer or shorter. Nothing here adjusts
// for the offset change; these cases exist to keep it that way.
func TestTheBoundaryIsWallClockAcrossDSTTransitions(t *testing.T) {
	nyc, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Fatalf("load location: %v", err)
	}
	// 2026-03-08 is the spring-forward date in America/New_York: 02:00 EST
	// becomes 03:00 EDT, so the wall clock never reads 02:30 that day.
	beforeStart := time.Date(2026, 3, 8, 6, 30, 0, 0, time.UTC).In(nyc) // 01:30 EST
	afterSkip := time.Date(2026, 3, 8, 7, 30, 0, 0, time.UTC).In(nyc)   // 03:30 EDT
	afterStart := time.Date(2026, 3, 8, 8, 30, 0, 0, time.UTC).In(nyc)  // 04:30 EDT
	yesterday := time.Date(2026, 3, 7, 10, 0, 0, 0, time.UTC).In(nyc)   // 05:00 EST, 7 March
	assertWallClock(t, beforeStart, "01:30")
	assertWallClock(t, afterSkip, "03:30")
	assertWallClock(t, afterStart, "04:30")

	four := mustParse(t, fourAM)
	if !four.Same(yesterday, beforeStart) {
		t.Error("a work day shortened by an hour is still one work day")
	}
	if four.Same(beforeStart, afterStart) {
		t.Error("04:30 on the wall clock is past a 04:00 start, whatever the offset did")
	}
	if got, want := four.Key(beforeStart), "2026-03-07"; got != want {
		t.Errorf("Key(01:30 on the short day) = %q, want %q", got, want)
	}

	// A start hour the wall clock skips entirely still begins the day: the
	// day it names is the one the clock is in when it next reads past it.
	skipped := mustParse(t, "02:30")
	if got, want := skipped.Key(afterSkip), "2026-03-08"; got != want {
		t.Errorf("Key(03:30, with a 02:30 start the clock skipped) = %q, want %q", got, want)
	}
	if got, want := skipped.Key(beforeStart), "2026-03-07"; got != want {
		t.Errorf("Key(01:30, with a 02:30 start) = %q, want %q", got, want)
	}

	// 2026-11-01 is the fall-back date: 01:30 happens twice, an hour apart in
	// real time and at the same time on the wall clock.
	firstOneThirty := time.Date(2026, 11, 1, 5, 30, 0, 0, time.UTC).In(nyc)  // 01:30 EDT
	secondOneThirty := time.Date(2026, 11, 1, 6, 30, 0, 0, time.UTC).In(nyc) // 01:30 EST
	assertWallClock(t, firstOneThirty, "01:30")
	assertWallClock(t, secondOneThirty, "01:30")
	if got, want := four.Key(firstOneThirty), "2026-10-31"; got != want {
		t.Errorf("Key(the first 01:30) = %q, want %q", got, want)
	}
	one := mustParse(t, "01:00")
	if !one.Same(firstOneThirty, secondOneThirty) {
		t.Error("the same wall-clock minute twice over is the same work day")
	}
	if got, want := one.Key(secondOneThirty), "2026-11-01"; got != want {
		t.Errorf("Key(the second 01:30, with a 01:00 start) = %q, want %q", got, want)
	}
}

func assertWallClock(t *testing.T, at time.Time, want string) {
	t.Helper()
	if got := at.Format("15:04"); got != want {
		t.Fatalf("the fixture reads %s on the wall clock, want %s", got, want)
	}
}
