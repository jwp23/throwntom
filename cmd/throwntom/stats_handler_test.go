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
	cases := map[int]string{1: "○ 1", 3: "◐ 3", 6: "● 6"}
	for count, want := range cases {
		if got := tierStyled(count, 2, 5); !strings.Contains(got, want) {
			t.Errorf("tierStyled(%d) = %q, want substring %q", count, got, want)
		}
	}
}
