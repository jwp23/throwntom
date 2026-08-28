package core

import (
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/eventlog"
)

func TestStatsReturnsDashboard(t *testing.T) {
	dir := t.TempDir()
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.eventsPath = dir + "/events.jsonl"

	result := c.execute("stats")
	if result.err != nil {
		t.Fatalf("stats failed: %v", result.err)
	}
	if result.message != "" {
		t.Fatalf("expected message empty, got: %s", result.message)
	}
	if result.stats == nil {
		t.Fatal("expected dashboard data in result")
	}
	if result.stats.Today.Pomodoros != 0 {
		t.Fatalf("expected 0 pomodoros, got %d", result.stats.Today.Pomodoros)
	}
}

func TestStatsWithEvents(t *testing.T) {
	dir := t.TempDir()
	eventsPath := dir + "/events.jsonl"
	w := eventlog.NewWriter(eventsPath)
	if err := w.Log("pomodoro_started", nil); err != nil {
		t.Fatal(err)
	}
	if err := w.Log("pomodoro_completed", nil); err != nil {
		t.Fatal(err)
	}

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.eventsPath = eventsPath

	result := c.execute("stats")
	if result.err != nil {
		t.Fatalf("stats failed: %v", result.err)
	}
	if result.stats == nil || result.stats.Today.Pomodoros != 1 {
		t.Fatalf("expected 1 pomodoro in dashboard, got %+v", result.stats)
	}
}

func TestStatsInHelp(t *testing.T) {
	help := Help()
	if !strings.Contains(help, "stats") {
		t.Fatal("expected stats command in help output")
	}
}

func newCoreWithEvents(t *testing.T) (*Core, string) {
	t.Helper()
	dir := t.TempDir()
	eventsPath := dir + "/events.jsonl"
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.eventsPath = eventsPath
	c.eventWriter = eventlog.NewWriter(eventsPath)
	return c, eventsPath
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
	c, path := newCoreWithEvents(t)
	c.execute("start")
	events := readEvents(t, path)
	if !hasEventType(events, "pomodoro_started") {
		t.Fatal("expected pomodoro_started event")
	}
}

func TestConfirmLogsCompletionAndStart(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.timer.CompletePeriod()
	c.execute("confirm")
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
	c, path := newCoreWithEvents(t)
	c.execute("start")
	c.execute("pause")
	c.execute("resume")
	events := readEvents(t, path)
	if !hasEventType(events, "paused") {
		t.Fatal("expected paused event")
	}
	if !hasEventType(events, "resumed") {
		t.Fatal("expected resumed event")
	}
}

func TestSnoozeLogsEvent(t *testing.T) {
	c, path := newCoreWithEvents(t)
	// Raise the morning reminder to enable the morning snooze path
	c.reminder.raise(reminderMorning)
	c.execute("snooze 5m")
	events := readEvents(t, path)
	if !hasEventType(events, "snoozed") {
		t.Fatal("expected snoozed event")
	}
	// The onTransition hook raises a fresh cycle reminder at awaiting_confirm,
	// so a second snooze there succeeds and logs its own event.
	c.execute(cmdStart)
	c.timer.CompletePeriod()
	result := c.execute("snooze 5m")
	if result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}
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
	// Cancel the outstanding snooze deadline so its timer doesn't fire
	// and log another event after the test has finished.
	c.reminder.cancel()
}

func TestSkipTodayLogsEvent(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute("skip-today")
	events := readEvents(t, path)
	if !hasEventType(events, "skipped_today") {
		t.Fatal("expected skipped_today event")
	}
}

func TestNoLogWhenWriterNil(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	// eventWriter is nil — should not panic
	c.execute("start")
	c.execute("pause")
	c.execute("resume")
}
