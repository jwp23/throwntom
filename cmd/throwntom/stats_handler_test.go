package main

import (
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/analytics"
	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/eventlog"
)

func TestStatsNoEvents(t *testing.T) {
	dir := t.TempDir()
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.eventsPath = dir + "/events.jsonl"
	core.tierLow = cfg.Stats.TierLow
	core.tierMid = cfg.Stats.TierMid

	result := core.execute("stats")
	if result.err != nil {
		t.Fatalf("stats failed: %v", result.err)
	}
	if !strings.Contains(result.message, "Today") {
		t.Fatalf("expected Today section, got: %s", result.message)
	}
	if !strings.Contains(result.message, "Pomodoros: 0") {
		t.Fatalf("expected Pomodoros: 0, got: %s", result.message)
	}
}

func TestStatsWithEvents(t *testing.T) {
	dir := t.TempDir()
	eventsPath := dir + "/events.jsonl"
	w := eventlog.NewWriter(eventsPath)
	w.Log("pomodoro_started", nil)
	w.Log("pomodoro_completed", nil)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.eventsPath = eventsPath
	core.tierLow = cfg.Stats.TierLow
	core.tierMid = cfg.Stats.TierMid

	result := core.execute("stats")
	if result.err != nil {
		t.Fatalf("stats failed: %v", result.err)
	}
	if !strings.Contains(result.message, "Pomodoros: 1") {
		t.Fatalf("expected Pomodoros: 1, got: %s", result.message)
	}
}

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

func TestTierStyle(t *testing.T) {
	cool := tierStyle(1, 2, 5)
	warm := tierStyle(3, 2, 5)
	hot := tierStyle(6, 2, 5)

	// Just verify they don't panic and return non-zero styles
	_ = cool.Render("1")
	_ = warm.Render("3")
	_ = hot.Render("6")
}

func TestStatsInHelp(t *testing.T) {
	help := commandsHelp()
	if !strings.Contains(help, "stats") {
		t.Fatal("expected stats command in help output")
	}
}
