package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/session"
	"github.com/jwp23/throwntom/v3/internal/task"
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

func TestNewTimerCoreDefaultsMorningPendingTrue(t *testing.T) {
	core := newTimerCore(config.Default(), noopNotifier{})
	if !core.state.isMorningPending() {
		t.Fatal("expected morning reminder pending by default")
	}
}

func TestNewTimerCoreRespectsMorningReminderPendingFalse(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false

	core := newTimerCore(cfg, noopNotifier{})
	if core.state.isMorningPending() {
		t.Fatal("expected morning reminder pending to be false")
	}
}

func TestBeginMorningLoopStartsWhenPendingTrue(t *testing.T) {
	state := &reminderState{morningPending: true}
	ctx, started := state.beginMorningLoop()
	if !started {
		t.Fatal("expected beginMorningLoop to start when morningPending is true but no loop running")
	}
	if ctx == nil {
		t.Fatal("expected non-nil context")
	}
	// Clean up
	state.stopMorningLoop()
}

func TestBeginMorningLoopRejectsDuplicateLoop(t *testing.T) {
	state := &reminderState{}
	ctx, started := state.beginMorningLoop()
	if !started {
		t.Fatal("expected first beginMorningLoop to start")
	}
	if ctx == nil {
		t.Fatal("expected non-nil context from first call")
	}

	_, startedAgain := state.beginMorningLoop()
	if startedAgain {
		t.Fatal("expected second beginMorningLoop to be rejected (duplicate prevention)")
	}
	// Clean up
	state.stopMorningLoop()
}

func TestNewCycleCommandResetsCycleProgressButKeepsDailyTotal(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})

	core.execute(cmdStart)
	core.cycle.CompletePeriod()
	before, _, _ := core.snapshot()
	if !strings.Contains(before, statusTodayPomodoros1) {
		t.Fatalf("expected baseline daily total, got %s", before)
	}

	result := core.execute("new-cycle")
	if result.err != nil {
		t.Fatalf("new-cycle command failed: %v", result.err)
	}

	after, _, _ := core.snapshot()
	if !strings.Contains(after, "Pomodoro") {
		t.Fatalf("expected Pomodoro state, got %s", after)
	}
	if !strings.Contains(after, "Cycle: 0/4") {
		t.Fatalf("expected cycle reset, got %s", after)
	}
	if !strings.Contains(after, statusTodayPomodoros1) {
		t.Fatalf("expected daily total preserved, got %s", after)
	}
}

func TestSaveSessionWritesValidJSON(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute(cmdStart)

	core.saveSession()

	raw, err := os.ReadFile(sessPath)
	if err != nil {
		t.Fatalf("read session file: %v", err)
	}
	var data session.Data
	if err := json.Unmarshal(raw, &data); err != nil {
		t.Fatalf("unmarshal session: %v", err)
	}
	if data.SavedAt.IsZero() {
		t.Fatal("expected non-zero SavedAt")
	}
}

func TestLoadSessionRestoresState(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute(cmdStart)
	core.cycle.CompletePeriod()
	core.saveSession()

	core2 := newTimerCore(cfg, noopNotifier{})
	core2.sessionPath = sessPath
	if err := core2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	status, _, _ := core2.snapshot()
	if !strings.Contains(status, "Confirm to continue") {
		t.Fatalf("expected Confirm to continue after restore, got %s", status)
	}
	if !strings.Contains(status, statusTodayPomodoros1) {
		t.Fatalf("expected completedToday=1, got %s", status)
	}
}

func TestLoadSessionDiscardsDifferentDay(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	yesterday := time.Now().Add(-24 * time.Hour)
	data := session.Data{
		SavedAt: yesterday,
	}
	raw, _ := json.Marshal(data)
	if err := os.WriteFile(sessPath, raw, 0o644); err != nil {
		t.Fatal(err)
	}

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	if err := core.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	status, _, _ := core.snapshot()
	if !strings.Contains(status, "Idle") {
		t.Fatalf("expected Idle for different-day session, got %s", status)
	}
}

func TestLoadSessionPreservesFocusedTaskOrder(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)
	tasksPath := filepath.Join(dir, "tasks.json")

	store, err := task.NewFileStore(tasksPath)
	if err != nil {
		t.Fatal(err)
	}
	t1, _ := store.Add("first task")
	t2, _ := store.Add("second task")
	t3, _ := store.Add("third task")

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.tasks = store
	core.execute(cmdStart)
	core.focused = []task.Task{t3, t1}
	core.saveSession()

	store2, _ := task.NewFileStore(tasksPath)
	core2 := newTimerCore(cfg, noopNotifier{})
	core2.sessionPath = sessPath
	core2.tasks = store2
	if err := core2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	focused := core2.focusedTasks()
	if len(focused) != 2 {
		t.Fatalf("expected 2 focused tasks, got %d", len(focused))
	}
	if focused[0].ID != t3.ID || focused[1].ID != t1.ID {
		t.Fatalf("expected focused order [%d, %d], got [%d, %d]", t3.ID, t1.ID, focused[0].ID, focused[1].ID)
	}
	_ = t2
}

func TestLoadSessionDropsStaleTaskIDs(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)
	tasksPath := filepath.Join(dir, "tasks.json")

	store, err := task.NewFileStore(tasksPath)
	if err != nil {
		t.Fatal(err)
	}
	t1, _ := store.Add("exists")

	data := session.Data{
		SavedAt:        time.Now(),
		FocusedTaskIDs: []int{t1.ID, 999},
	}
	raw, _ := json.Marshal(data)
	if err := os.WriteFile(sessPath, raw, 0o644); err != nil {
		t.Fatal(err)
	}

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.tasks = store
	if err := core.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	focused := core.focusedTasks()
	if len(focused) != 1 {
		t.Fatalf("expected 1 focused task (stale dropped), got %d", len(focused))
	}
	if focused[0].ID != t1.ID {
		t.Fatalf("expected task %d, got %d", t1.ID, focused[0].ID)
	}
}

func TestExecuteCommandSavesSession(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath

	core.executeCommand(cmdStart)

	if _, err := os.Stat(sessPath); os.IsNotExist(err) {
		t.Fatal("expected session file to be created after executeCommand")
	}
}

func TestStopSavesSession(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute(cmdStart)

	core.stop()

	if _, err := os.Stat(sessPath); os.IsNotExist(err) {
		t.Fatal("expected session file to be created on stop")
	}
}

func TestLoadSessionSuppressesMorningReminder(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute(cmdStart)
	core.saveSession()

	cfg2 := config.Default()
	core2 := newTimerCore(cfg2, noopNotifier{})
	core2.sessionPath = sessPath
	if err := core2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	dayKey := time.Now().Format("2006-01-02")
	core2.state.mu.Lock()
	gotDay := core2.state.lastTriggerDay
	core2.state.mu.Unlock()
	if gotDay != dayKey {
		t.Fatalf("expected lastTriggerDay=%s, got %s", dayKey, gotDay)
	}
}

func TestSaveLoadExpiredTimerTransitionsToAwaitingConfirm(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute(cmdStart)
	core.saveSession()

	data, err := session.Load(sessPath)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	data.App.PhaseEndAt = time.Now().Add(-5 * time.Second)
	_ = session.Save(sessPath, data)

	core2 := newTimerCore(cfg, noopNotifier{})
	core2.sessionPath = sessPath
	if err := core2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	state := core2.cycle.State()
	if state != engine.AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm for expired timer, got %s", state)
	}
	core2.cycle.Stop()
}

func TestSaveLoadPausedPreservesRemainingDuration(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute(cmdStart)
	core.execute("pause")
	core.saveSession()

	core2 := newTimerCore(cfg, noopNotifier{})
	core2.sessionPath = sessPath
	if err := core2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	state := core2.cycle.State()
	if state != engine.Paused {
		t.Fatalf("expected Paused, got %s", state)
	}
	core2.execute("resume")
	state = core2.cycle.State()
	if state != engine.Work {
		t.Fatalf("expected Work after resume, got %s", state)
	}
	core2.cycle.Stop()
}

func TestSaveLoadCompletedTodayPersists(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath

	core.execute(cmdStart)
	for i := 0; i < 3; i++ {
		core.cycle.CompletePeriod()
		core.execute("confirm")
		core.cycle.CompletePeriod()
		core.execute("confirm")
	}

	status, _, _ := core.snapshot()
	if !strings.Contains(status, "Today: 3") {
		t.Fatalf("expected Today: 3 before save, got %s", status)
	}
	core.saveSession()

	core2 := newTimerCore(cfg, noopNotifier{})
	core2.sessionPath = sessPath
	if err := core2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	status2, _, _ := core2.snapshot()
	if !strings.Contains(status2, "Today: 3") {
		t.Fatalf("expected Today: 3 after load, got %s", status2)
	}
	core2.cycle.Stop()
}

func TestSnapshotResetsCompletedTodayOnDayRollover(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})

	yesterday := time.Date(2026, 3, 5, 17, 0, 0, 0, time.Local)
	core.now = func() time.Time { return yesterday }

	core.executeCommand(cmdStart)
	core.cycle.CompletePeriod()

	status, _, _ := core.snapshot()
	if !strings.Contains(status, statusTodayPomodoros1) {
		t.Fatalf("expected today's pomodoros=1 yesterday, got %s", status)
	}

	today := time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)
	core.now = func() time.Time { return today }

	status2, _, _ := core.snapshot()
	if !strings.Contains(status2, statusTodayPomodoros0) {
		t.Fatalf("expected today's pomodoros=0 after day rollover, got %s", status2)
	}
}

func TestStartBeginsMorningLoopWhenPendingAndIdle(t *testing.T) {
	cfg := config.Default()
	core := newTimerCore(cfg, noopNotifier{})
	// Monday at 10:00 — after default schedule 09:15
	core.now = func() time.Time { return time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local) }

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	core.start(ctx)
	defer core.stop()

	core.state.mu.Lock()
	hasCancel := core.state.morningCancel != nil
	core.state.mu.Unlock()
	if !hasCancel {
		t.Fatal("expected morning loop to be running after start with morningPending=true and idle engine")
	}
}

func TestStartSkipsMorningLoopWhenNotPending(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	core.start(ctx)
	defer core.stop()

	core.state.mu.Lock()
	hasCancel := core.state.morningCancel != nil
	core.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected no morning loop when morningPending=false")
	}
}

func TestStartSkipsMorningLoopWhenEngineNotIdle(t *testing.T) {
	cfg := config.Default()
	core := newTimerCore(cfg, noopNotifier{})
	core.execute(cmdStart) // engine transitions to Work, stopMorningLoop clears morningPending

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	core.start(ctx)
	defer core.stop()

	core.state.mu.Lock()
	hasCancel := core.state.morningCancel != nil
	core.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected no morning loop when engine is not idle")
	}
}

func TestStartSkipsMorningLoopBeforeScheduledTime(t *testing.T) {
	cfg := config.Default()
	core := newTimerCore(cfg, noopNotifier{})
	// Monday at 08:00 — before default schedule 09:15
	core.now = func() time.Time { return time.Date(2026, 3, 2, 8, 0, 0, 0, time.Local) }

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	core.start(ctx)
	defer core.stop()

	core.state.mu.Lock()
	hasCancel := core.state.morningCancel != nil
	core.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected no morning loop before scheduled time")
	}
}

func TestStartBeginsMorningLoopAfterScheduledTime(t *testing.T) {
	cfg := config.Default()
	core := newTimerCore(cfg, noopNotifier{})
	// Monday at 11:30 — after default schedule 09:15
	core.now = func() time.Time { return time.Date(2026, 3, 2, 11, 30, 0, 0, time.Local) }

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	core.start(ctx)
	defer core.stop()

	core.state.mu.Lock()
	hasCancel := core.state.morningCancel != nil
	core.state.mu.Unlock()
	if !hasCancel {
		t.Fatal("expected morning loop to be running after scheduled time")
	}
}

func TestMorningSnoozeRestartsLoopAfterExpiry(t *testing.T) {
	cfg := config.Default()
	core := newTimerCore(cfg, noopNotifier{})
	core.now = func() time.Time { return time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local) }

	// Start morning loop manually to simulate scheduler trigger
	startMorningLoop(core.state, core.repeatInterval, core.notifier)

	// Snooze for a tiny duration
	result := core.execute("snooze 1ms")
	if result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}
	if !strings.Contains(result.message, "morning reminder snoozed") {
		t.Fatalf("expected morning snooze message, got %q", result.message)
	}

	// Morning loop should be stopped immediately after snooze
	core.state.mu.Lock()
	hasCancel := core.state.morningCancel != nil
	core.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected morning loop to be stopped during snooze")
	}

	// Wait for snooze to expire and goroutine to re-trigger
	time.Sleep(50 * time.Millisecond)

	core.state.mu.Lock()
	hasCancel = core.state.morningCancel != nil
	core.state.mu.Unlock()
	if !hasCancel {
		t.Fatal("expected morning loop to be restarted after snooze expiry")
	}
	core.state.stopMorningLoop()
}

func TestMorningSnoozeSkipsRestartIfNotIdle(t *testing.T) {
	cfg := config.Default()
	core := newTimerCore(cfg, noopNotifier{})
	core.now = func() time.Time { return time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local) }

	// Start morning loop manually
	startMorningLoop(core.state, core.repeatInterval, core.notifier)

	// Snooze for a tiny duration
	result := core.execute("snooze 1ms")
	if result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}

	// Start a pomodoro before snooze expires
	core.execute(cmdStart)
	if core.cycle.State() != engine.Work {
		t.Fatal("expected engine to be in Work state")
	}

	// Wait for snooze goroutine to fire
	time.Sleep(50 * time.Millisecond)

	// Morning loop should NOT restart since engine is not idle
	core.state.mu.Lock()
	hasCancel := core.state.morningCancel != nil
	core.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected morning loop to NOT restart when engine is not idle")
	}
	core.cycle.Stop()
}

func TestMorningSnoozeStopMidSnooze(t *testing.T) {
	cfg := config.Default()
	core := newTimerCore(cfg, noopNotifier{})
	core.now = func() time.Time { return time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local) }

	// Start morning loop manually
	startMorningLoop(core.state, core.repeatInterval, core.notifier)

	// Snooze for a longer duration
	result := core.execute("snooze 100ms")
	if result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}

	// Start a pomodoro (which calls stopMorningLoop + clearSnooze)
	core.execute(cmdStart)

	// Wait for the snooze goroutine to fire
	time.Sleep(150 * time.Millisecond)

	// The goroutine should not interfere — engine is not idle
	core.state.mu.Lock()
	hasCancel := core.state.morningCancel != nil
	core.state.mu.Unlock()
	if hasCancel {
		t.Fatal("expected no morning loop interference after start during snooze")
	}
	core.cycle.Stop()
}

func TestParseSnoozeDurationBareNumber(t *testing.T) {
	tests := []struct {
		name    string
		input   []string
		want    time.Duration
		wantErr bool
	}{
		{"bare 5 means 5m", []string{"snooze", "5"}, 5 * time.Minute, false},
		{"bare 10 means 10m", []string{"snooze", "10"}, 10 * time.Minute, false},
		{"explicit 5m still works", []string{"snooze", "5m"}, 5 * time.Minute, false},
		{"explicit 1h still works", []string{"snooze", "1h"}, time.Hour, false},
		{"invalid string errors", []string{"snooze", "abc"}, 0, true},
		{"missing arg errors", []string{"snooze"}, 0, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := parseSnoozeDuration(tt.input)
			if tt.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("got %v, want %v", got, tt.want)
			}
		})
	}
}

func TestSessionSavedAfterMidnightResetsOnReload(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)
	cfg := config.Default()
	cfg.MorningReminderPending = false

	yesterday := time.Date(2026, 3, 5, 17, 0, 0, 0, time.Local)
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.now = func() time.Time { return yesterday }

	core.executeCommand(cmdStart)
	core.cycle.CompletePeriod()
	core.executeCommand("pause")

	afterMidnight := time.Date(2026, 3, 6, 0, 5, 0, 0, time.Local)
	core.now = func() time.Time { return afterMidnight }
	core.stop()

	today := time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)
	core2 := newTimerCore(cfg, noopNotifier{})
	core2.sessionPath = sessPath
	core2.now = func() time.Time { return today }
	if err := core2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}

	status, _, _ := core2.snapshot()
	if !strings.Contains(status, statusTodayPomodoros0) {
		t.Fatalf("expected today's pomodoros=0 after midnight reload, got %s", status)
	}
}
