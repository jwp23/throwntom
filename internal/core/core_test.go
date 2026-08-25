package core

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

const (
	testSessionFile       = "session.json"
	cmdStart              = "start"
	fmtLoadSession        = "loadSession: %v"
	statusTodayPomodoros1 = "Today: 1"
	statusTodayPomodoros0 = "Today: 0"
	fmtSnoozeFailed       = "snooze failed: %v"
)

type noopNotifier struct{}

func (noopNotifier) PlaySound(string) error {
	return nil
}

func TestNextStageWhenAwaiting(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdStart)
	c.cycle.CompletePeriod()

	next, dur, ok := c.NextStage()
	if !ok {
		t.Fatal("expected next stage while awaiting confirm")
	}
	if next != engine.ShortBreak || dur != 5*time.Minute {
		t.Fatalf("next stage = %s %s", next, dur)
	}
}

func TestNextStageAbsentOutsideAwaiting(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	if _, _, ok := c.NextStage(); ok {
		t.Fatal("expected no next stage when idle")
	}
	c.execute(cmdStart)
	if _, _, ok := c.NextStage(); ok {
		t.Fatal("expected no next stage during work")
	}
}

func TestStatusLineUnchangedInAwaiting(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdStart)
	c.cycle.CompletePeriod()

	status, state, _ := c.Status()
	if state != engine.AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm, got %s", state)
	}
	if !strings.Contains(status, "Confirm to continue") {
		t.Fatalf("expected status line to retain label, got %s", status)
	}
	if !strings.Contains(status, "Today: 1") {
		t.Fatalf("expected status line to retain stats, got %s", status)
	}
	if strings.Contains(status, "Next:") {
		t.Fatalf("status line should not contain the Next: secondary label, got %s", status)
	}
}

func TestNewCoreDefaultsMorningPendingTrue(t *testing.T) {
	c := newCore(config.Default(), noopNotifier{})
	if !c.state.isMorningPending() {
		t.Fatal("expected morning reminder pending by default")
	}
}

func TestNewCoreRespectsMorningReminderPendingFalse(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false

	c := newCore(cfg, noopNotifier{})
	if c.state.isMorningPending() {
		t.Fatal("expected morning reminder pending to be false")
	}
}

func TestStatusResetsCompletedTodayOnDayRollover(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})

	yesterday := time.Date(2026, 3, 5, 17, 0, 0, 0, time.Local)
	c.setNow(func() time.Time { return yesterday })

	c.Execute(cmdStart)
	c.cycle.CompletePeriod()

	status, _, _ := c.Status()
	if !strings.Contains(status, statusTodayPomodoros1) {
		t.Fatalf("expected today's pomodoros=1 yesterday, got %s", status)
	}

	today := time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)
	c.setNow(func() time.Time { return today })

	status2, _, _ := c.Status()
	if !strings.Contains(status2, statusTodayPomodoros0) {
		t.Fatalf("expected today's pomodoros=0 after day rollover, got %s", status2)
	}
}

func TestNewWiresStoresAndSession(t *testing.T) {
	dir := t.TempDir()
	paths := Paths{
		Tasks:   filepath.Join(dir, "tasks.json"),
		Session: filepath.Join(dir, "session.json"),
		Events:  filepath.Join(dir, "events.jsonl"),
	}
	cfg := config.Default()
	cfg.MorningReminderPending = false

	c, err := New(cfg, noopNotifier{}, paths)
	if err != nil {
		t.Fatal(err)
	}
	if res := c.execute("task add write tests"); res.err != nil {
		t.Fatal(res.err)
	}
	c.Execute("new-cycle")
	if _, err := os.Stat(paths.Session); err != nil {
		t.Fatalf("expected session file: %v", err)
	}
	if events := readEvents(t, paths.Events); len(events) != 1 || events[0].Type != "pomodoro_started" {
		t.Fatalf("expected one pomodoro_started event, got %+v", events)
	}
	if len(c.tasks.Active()) != 1 {
		t.Fatal("expected task store to persist the added task")
	}
}

func TestCancelFocusClearsPromptAndReportsStatus(t *testing.T) {
	c := newTestCoreWithTasks(t)
	c.execute("task add something")
	c.execute("start") // enters the focus prompt

	resp := c.CancelFocus()

	if c.FocusPromptPending() {
		t.Fatal("expected focus prompt to be cancelled")
	}
	if resp.FocusPrompt != "" {
		t.Fatalf("expected no focus prompt in response, got %q", resp.FocusPrompt)
	}
	if !strings.Contains(resp.Message, "cancelled") {
		t.Fatalf("expected cancellation message, got %q", resp.Message)
	}
	if resp.EngineState != engine.Idle {
		t.Fatalf("expected idle engine state, got %s", resp.EngineState)
	}
	if !strings.Contains(resp.StatusLine, "Idle") {
		t.Fatalf("expected status line in response, got %q", resp.StatusLine)
	}
	if len(resp.Focused) != 0 {
		t.Fatalf("expected no focused tasks, got %v", resp.Focused)
	}
}

func TestDefaultPaths(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)

	paths, err := DefaultPaths()
	if err != nil {
		t.Fatalf("DefaultPaths: %v", err)
	}
	if !strings.Contains(paths.Tasks, "tasks.json") {
		t.Fatalf("expected tasks.json in path, got %s", paths.Tasks)
	}
	if !strings.Contains(paths.Session, "session.json") {
		t.Fatalf("expected session.json in path, got %s", paths.Session)
	}
	if !strings.Contains(paths.Events, "events.jsonl") {
		t.Fatalf("expected events.jsonl in path, got %s", paths.Events)
	}
	if !strings.Contains(paths.Tasks, "throwntom") {
		t.Fatalf("expected throwntom in tasks path, got %s", paths.Tasks)
	}
	if !strings.Contains(paths.Session, "throwntom") {
		t.Fatalf("expected throwntom in session path, got %s", paths.Session)
	}
	if !strings.Contains(paths.Events, "throwntom") {
		t.Fatalf("expected throwntom in events path, got %s", paths.Events)
	}
}

func TestFriendlyStateName(t *testing.T) {
	cases := map[engine.State]string{
		engine.Work:            "pomodoro",
		engine.ShortBreak:      "short break",
		engine.LongBreak:       "long break",
		engine.Idle:            "idle",
		engine.Paused:          "paused",
		engine.AwaitingConfirm: "awaiting confirmation",
	}
	for state, want := range cases {
		if got := FriendlyStateName(state); got != want {
			t.Fatalf("FriendlyStateName(%s) = %q, want %q", state, got, want)
		}
	}
}

func TestPauseWhenIdleIsAnError(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	if res := c.execute("pause"); !errors.Is(res.err, errNotRunning) {
		t.Fatalf("expected errNotRunning, got %v", res.err)
	}
	c.execute("new-cycle")
	if res := c.execute("resume"); !errors.Is(res.err, errNotPaused) {
		t.Fatalf("expected errNotPaused, got %v", res.err)
	}
}
