package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v2/internal/config"
	"github.com/jwp23/throwntom/v2/internal/engine"
	"github.com/jwp23/throwntom/v2/internal/session"
	"github.com/jwp23/throwntom/v2/internal/task"
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

	core.execute("start")
	core.cycle.CompletePeriod()
	before, _ := core.snapshot()
	if !strings.Contains(before, "today's pomodoros=1") {
		t.Fatalf("expected baseline daily total, got %s", before)
	}

	result := core.execute("new-cycle")
	if result.err != nil {
		t.Fatalf("new-cycle command failed: %v", result.err)
	}

	after, _ := core.snapshot()
	if !strings.Contains(after, "pomodoro") {
		t.Fatalf("expected pomodoro state, got %s", after)
	}
	if !strings.Contains(after, "pomodoros=0/4") {
		t.Fatalf("expected cycle reset, got %s", after)
	}
	if !strings.Contains(after, "today's pomodoros=1") {
		t.Fatalf("expected daily total preserved, got %s", after)
	}
}

func TestSaveSessionWritesValidJSON(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, "session.json")

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute("start")

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
	sessPath := filepath.Join(dir, "session.json")

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute("start")
	core.cycle.CompletePeriod()
	core.saveSession()

	core2 := newTimerCore(cfg, noopNotifier{})
	core2.sessionPath = sessPath
	if err := core2.loadSession(); err != nil {
		t.Fatalf("loadSession: %v", err)
	}
	status, _ := core2.snapshot()
	if !strings.Contains(status, "awaiting-confirm") {
		t.Fatalf("expected awaiting-confirm after restore, got %s", status)
	}
	if !strings.Contains(status, "today's pomodoros=1") {
		t.Fatalf("expected completedToday=1, got %s", status)
	}
}

func TestLoadSessionDiscardsDifferentDay(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, "session.json")

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
		t.Fatalf("loadSession: %v", err)
	}
	status, _ := core.snapshot()
	if !strings.Contains(status, "idle") {
		t.Fatalf("expected idle for different-day session, got %s", status)
	}
}

func TestLoadSessionPreservesFocusedTaskOrder(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, "session.json")
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
	core.execute("start")
	core.focused = []task.Task{t3, t1}
	core.saveSession()

	store2, _ := task.NewFileStore(tasksPath)
	core2 := newTimerCore(cfg, noopNotifier{})
	core2.sessionPath = sessPath
	core2.tasks = store2
	if err := core2.loadSession(); err != nil {
		t.Fatalf("loadSession: %v", err)
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
	sessPath := filepath.Join(dir, "session.json")
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
		t.Fatalf("loadSession: %v", err)
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
	sessPath := filepath.Join(dir, "session.json")

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath

	core.executeCommand("start")

	if _, err := os.Stat(sessPath); os.IsNotExist(err) {
		t.Fatal("expected session file to be created after executeCommand")
	}
}

func TestStopSavesSession(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, "session.json")

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute("start")

	core.stop()

	if _, err := os.Stat(sessPath); os.IsNotExist(err) {
		t.Fatal("expected session file to be created on stop")
	}
}

func TestLoadSessionSuppressesMorningReminder(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, "session.json")

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute("start")
	core.saveSession()

	cfg2 := config.Default()
	core2 := newTimerCore(cfg2, noopNotifier{})
	core2.sessionPath = sessPath
	if err := core2.loadSession(); err != nil {
		t.Fatalf("loadSession: %v", err)
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
	sessPath := filepath.Join(dir, "session.json")

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute("start")
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
		t.Fatalf("loadSession: %v", err)
	}
	state := core2.cycle.State()
	if state != engine.AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm for expired timer, got %s", state)
	}
	core2.cycle.Stop()
}

func TestSaveLoadPausedPreservesRemainingDuration(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, "session.json")

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.execute("start")
	core.execute("pause")
	core.saveSession()

	core2 := newTimerCore(cfg, noopNotifier{})
	core2.sessionPath = sessPath
	if err := core2.loadSession(); err != nil {
		t.Fatalf("loadSession: %v", err)
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
	sessPath := filepath.Join(dir, "session.json")

	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath

	core.execute("start")
	for i := 0; i < 3; i++ {
		core.cycle.CompletePeriod()
		core.execute("confirm")
		core.cycle.CompletePeriod()
		core.execute("confirm")
	}

	status, _ := core.snapshot()
	if !strings.Contains(status, "today's pomodoros=3") {
		t.Fatalf("expected 3 completed before save, got %s", status)
	}
	core.saveSession()

	core2 := newTimerCore(cfg, noopNotifier{})
	core2.sessionPath = sessPath
	if err := core2.loadSession(); err != nil {
		t.Fatalf("loadSession: %v", err)
	}
	status2, _ := core2.snapshot()
	if !strings.Contains(status2, "today's pomodoros=3") {
		t.Fatalf("expected 3 completed after load, got %s", status2)
	}
	core2.cycle.Stop()
}

func TestSnapshotResetsCompletedTodayOnDayRollover(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newTimerCore(cfg, noopNotifier{})

	yesterday := time.Date(2026, 3, 5, 17, 0, 0, 0, time.Local)
	core.now = func() time.Time { return yesterday }

	core.executeCommand("start")
	core.cycle.CompletePeriod()

	status, _ := core.snapshot()
	if !strings.Contains(status, "today's pomodoros=1") {
		t.Fatalf("expected today's pomodoros=1 yesterday, got %s", status)
	}

	today := time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)
	core.now = func() time.Time { return today }

	status2, _ := core.snapshot()
	if !strings.Contains(status2, "today's pomodoros=0") {
		t.Fatalf("expected today's pomodoros=0 after day rollover, got %s", status2)
	}
}

func TestStartBeginsMorningLoopWhenPendingAndIdle(t *testing.T) {
	cfg := config.Default()
	core := newTimerCore(cfg, noopNotifier{})

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
	core.execute("start") // engine transitions to Work, stopMorningLoop clears morningPending

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

func TestSessionSavedAfterMidnightResetsOnReload(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, "session.json")
	cfg := config.Default()
	cfg.MorningReminderPending = false

	yesterday := time.Date(2026, 3, 5, 17, 0, 0, 0, time.Local)
	core := newTimerCore(cfg, noopNotifier{})
	core.sessionPath = sessPath
	core.now = func() time.Time { return yesterday }

	core.executeCommand("start")
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
		t.Fatalf("loadSession: %v", err)
	}

	status, _ := core2.snapshot()
	if !strings.Contains(status, "today's pomodoros=0") {
		t.Fatalf("expected today's pomodoros=0 after midnight reload, got %s", status)
	}
}
