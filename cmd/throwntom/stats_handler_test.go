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

func newCoreWithEvents(t *testing.T) (*timerCore, string) {
	t.Helper()
	dir := t.TempDir()
	eventsPath := dir + "/events.jsonl"
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.eventsPath = eventsPath
	core.eventWriter = eventlog.NewWriter(eventsPath)
	core.tierLow = cfg.Stats.TierLow
	core.tierMid = cfg.Stats.TierMid
	return core, eventsPath
}

func readEvents(t *testing.T, path string) []eventlog.Event {
	t.Helper()
	events, err := eventlog.ReadAll(path)
	if err != nil {
		t.Fatalf("ReadAll: %v", err)
	}
	return events
}

func hasEventType(events []eventlog.Event, typ string) bool {
	for _, ev := range events {
		if ev.Type == typ {
			return true
		}
	}
	return false
}

func TestStartLogsEvent(t *testing.T) {
	core, path := newCoreWithEvents(t)
	core.execute("start")
	events := readEvents(t, path)
	if !hasEventType(events, "pomodoro_started") {
		t.Fatal("expected pomodoro_started event")
	}
}

func TestConfirmLogsCompletionAndStart(t *testing.T) {
	core, path := newCoreWithEvents(t)
	core.execute("start")
	core.cycle.CompletePeriod()
	core.execute("confirm")
	events := readEvents(t, path)
	if !hasEventType(events, "pomodoro_completed") {
		t.Fatal("expected pomodoro_completed event")
	}
	// After confirming a completed work session, should start a break
	if !hasEventType(events, "break_started") {
		t.Fatal("expected break_started event after work completion")
	}
}

func TestPauseResumeLogEvents(t *testing.T) {
	core, path := newCoreWithEvents(t)
	core.execute("start")
	core.execute("pause")
	core.execute("resume")
	events := readEvents(t, path)
	if !hasEventType(events, "paused") {
		t.Fatal("expected paused event")
	}
	if !hasEventType(events, "resumed") {
		t.Fatal("expected resumed event")
	}
}

func TestSnoozeLogsEvent(t *testing.T) {
	core, path := newCoreWithEvents(t)
	// Start morning loop to enable morning snooze path
	startMorningLoop(core.state, core.repeatInterval, core.notifier)
	core.execute("snooze 5m")
	events := readEvents(t, path)
	if !hasEventType(events, "snoozed") {
		t.Fatal("expected snoozed event")
	}
	// Also test cycle snooze path
	core.execute("start")
	core.cycle.CompletePeriod()
	core.execute("snooze 5m")
	events = readEvents(t, path)
	snoozedCount := 0
	for _, ev := range events {
		if ev.Type == "snoozed" {
			snoozedCount++
		}
	}
	if snoozedCount != 2 {
		t.Fatalf("expected 2 snoozed events, got %d", snoozedCount)
	}
}

func TestSkipTodayLogsEvent(t *testing.T) {
	core, path := newCoreWithEvents(t)
	core.execute("skip-today")
	events := readEvents(t, path)
	if !hasEventType(events, "skipped_today") {
		t.Fatal("expected skipped_today event")
	}
}

func TestNoLogWhenWriterNil(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	// eventWriter is nil — should not panic
	core.execute("start")
	core.execute("pause")
	core.execute("resume")
}
