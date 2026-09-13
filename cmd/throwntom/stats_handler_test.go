package main

import (
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/analytics"
)

func TestRenderDashboard(t *testing.T) {
	now := time.Date(2026, 3, 19, 14, 0, 0, 0, time.Local)
	dash := analytics.Dashboard{
		Today: analytics.PeriodStats{
			Pomodoros:    5,
			FocusMinutes: 125,
			Pauses:       1,
			Snoozes:      0,
		},
		ThisWeek: analytics.PeriodStats{
			Pomodoros:    23,
			FocusMinutes: 575,
			DailyCounts: []analytics.DayCount{
				{Date: time.Date(2026, 3, 16, 0, 0, 0, 0, time.Local), Count: 4},
				{Date: time.Date(2026, 3, 17, 0, 0, 0, 0, time.Local), Count: 6},
			},
		},
		Streaks: analytics.StreakStats{
			Current: 12,
			Longest: 28,
		},
		Patterns: analytics.PatternStats{
			BestDay:    time.Tuesday,
			BestHour:   10,
			SnoozeRate: 0.3,
			PauseRate:  0.1,
		},
	}

	output := renderDashboard(dash, now, 2, 5)
	if !strings.Contains(output, "Today") {
		t.Fatalf("expected Today section, got: %s", output)
	}
	if !strings.Contains(output, "2h 5m") {
		t.Fatalf("expected 2h 5m focus, got: %s", output)
	}
	if !strings.Contains(output, "Streaks") {
		t.Fatalf("expected Streaks section, got: %s", output)
	}
	if !strings.Contains(output, "Current: 12") {
		t.Fatalf("expected Current: 12, got: %s", output)
	}
	lines := strings.Split(output, "\n")
	if len(lines) < 5 {
		t.Fatalf("expected multi-line output, got %d lines", len(lines))
	}
}

// Tier is carried by a glyph as well as colour so the dashboard reads without colour vision.
func TestTierStyledCarriesGlyph(t *testing.T) {
	cases := map[int]string{1: "○ 1", 2: "○ 2", 3: "◐ 3", 5: "◐ 5", 6: "● 6"}
	for count, want := range cases {
		if got := tierStyled(count, 2, 5); !strings.Contains(got, want) {
			t.Errorf("tierStyled(%d) = %q, want substring %q", count, got, want)
		}
	}
}

// The this-month section only prints a per-day average once there are
// pomodoros to average, and the average itself must be a real division, not
// some other arithmetic op standing in for one.
func TestRenderDashboardMonthAverage(t *testing.T) {
	now := time.Date(2026, 3, 4, 9, 0, 0, 0, time.Local) // day-of-month 4
	dash := analytics.Dashboard{
		ThisMonth: analytics.PeriodStats{Pomodoros: 10, FocusMinutes: 250},
	}

	output := renderDashboard(dash, now, 2, 5)
	if !strings.Contains(output, "Avg: 2.5/day") {
		t.Fatalf("expected Avg: 2.5/day (10 pomodoros / day 4), got: %s", output)
	}
}

// The best-hour range is reported as an open interval [hour, hour+1); the
// upper bound must actually be hour+1, not some other arithmetic result.
func TestRenderDashboardPatternsBestHourRange(t *testing.T) {
	now := time.Date(2026, 3, 4, 9, 0, 0, 0, time.Local)
	dash := analytics.Dashboard{
		AllTime: analytics.PeriodStats{Pomodoros: 1},
		Patterns: analytics.PatternStats{
			BestDay:  time.Monday,
			BestHour: 10,
		},
	}

	output := renderDashboard(dash, now, 2, 5)
	if !strings.Contains(output, "Best hour: 10:00-11:00") {
		t.Fatalf("expected Best hour: 10:00-11:00, got: %s", output)
	}
}

// monthlyAverageSuffix guards its division against a zero day count. Real
// callers pass now.Day(), which time.Time never reports as zero, so this
// exercises the guard directly rather than through a clock that can't reach it.
func TestMonthlyAverageSuffix(t *testing.T) {
	if got := monthlyAverageSuffix(10, 4); got != "    Avg: 2.5/day" {
		t.Errorf("monthlyAverageSuffix(10, 4) = %q, want \"    Avg: 2.5/day\"", got)
	}
	if got := monthlyAverageSuffix(5, 0); got != "" {
		t.Errorf("monthlyAverageSuffix(5, 0) = %q, want empty string (guard against dividing by zero)", got)
	}
}
