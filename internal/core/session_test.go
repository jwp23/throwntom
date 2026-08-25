package core

import (
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

func TestSaveSessionWritesValidJSON(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	c.execute(cmdStart)

	c.saveSession()

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
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	c.execute(cmdStart)
	c.cycle.CompletePeriod()
	c.saveSession()

	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = sessPath
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	status, _, _ := c2.Status()
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
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	if err := c.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	status, _, _ := c.Status()
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
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	c.tasks = store
	c.execute(cmdStart)
	c.focused = []task.Task{t3, t1}
	c.saveSession()

	store2, _ := task.NewFileStore(tasksPath)
	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = sessPath
	c2.tasks = store2
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	focused := c2.Focused()
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
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	c.tasks = store
	if err := c.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	focused := c.Focused()
	if len(focused) != 1 {
		t.Fatalf("expected 1 focused task (stale dropped), got %d", len(focused))
	}
	if focused[0].ID != t1.ID {
		t.Fatalf("expected task %d, got %d", t1.ID, focused[0].ID)
	}
}

func TestExecuteSavesSession(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath

	c.Execute(cmdStart)

	if _, err := os.Stat(sessPath); os.IsNotExist(err) {
		t.Fatal("expected session file to be created after Execute")
	}
}

func TestStopSavesSession(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	c.execute(cmdStart)

	c.Stop()

	if _, err := os.Stat(sessPath); os.IsNotExist(err) {
		t.Fatal("expected session file to be created on stop")
	}
}

func TestLoadSessionSuppressesMorningReminder(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	c.execute(cmdStart)
	c.saveSession()

	cfg2 := config.Default()
	c2 := newCore(cfg2, noopNotifier{})
	c2.sessionPath = sessPath
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	dayKey := time.Now().Format("2006-01-02")
	c2.state.mu.Lock()
	gotDay := c2.state.lastTriggerDay
	c2.state.mu.Unlock()
	if gotDay != dayKey {
		t.Fatalf("expected lastTriggerDay=%s, got %s", dayKey, gotDay)
	}
}

func TestSaveLoadExpiredTimerTransitionsToAwaitingConfirm(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	c.execute(cmdStart)
	c.saveSession()

	data, err := session.Load(sessPath)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	data.App.PhaseEndAt = time.Now().Add(-5 * time.Second)
	_ = session.Save(sessPath, data)

	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = sessPath
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	state := c2.cycle.State()
	if state != engine.AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm for expired timer, got %s", state)
	}
	c2.cycle.Stop()
}

func TestSaveLoadPausedPreservesRemainingDuration(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	c.execute(cmdStart)
	c.execute("pause")
	c.saveSession()

	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = sessPath
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	state := c2.cycle.State()
	if state != engine.Paused {
		t.Fatalf("expected Paused, got %s", state)
	}
	c2.execute("resume")
	state = c2.cycle.State()
	if state != engine.Work {
		t.Fatalf("expected Work after resume, got %s", state)
	}
	c2.cycle.Stop()
}

func TestSaveLoadCompletedTodayPersists(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath

	c.execute(cmdStart)
	for i := 0; i < 3; i++ {
		c.cycle.CompletePeriod()
		c.execute("confirm")
		c.cycle.CompletePeriod()
		c.execute("confirm")
	}

	status, _, _ := c.Status()
	if !strings.Contains(status, "Today: 3") {
		t.Fatalf("expected Today: 3 before save, got %s", status)
	}
	c.saveSession()

	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = sessPath
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	status2, _, _ := c2.Status()
	if !strings.Contains(status2, "Today: 3") {
		t.Fatalf("expected Today: 3 after load, got %s", status2)
	}
	c2.cycle.Stop()
}

func TestSessionSavedAfterMidnightResetsOnReload(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)
	cfg := config.Default()
	cfg.MorningReminderPending = false

	yesterday := time.Date(2026, 3, 5, 17, 0, 0, 0, time.Local)
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	c.now = func() time.Time { return yesterday }

	c.Execute(cmdStart)
	c.cycle.CompletePeriod()
	c.Execute("pause")

	afterMidnight := time.Date(2026, 3, 6, 0, 5, 0, 0, time.Local)
	c.now = func() time.Time { return afterMidnight }
	c.Stop()

	today := time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)
	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = sessPath
	c2.now = func() time.Time { return today }
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}

	status, _, _ := c2.Status()
	if !strings.Contains(status, statusTodayPomodoros0) {
		t.Fatalf("expected today's pomodoros=0 after midnight reload, got %s", status)
	}
}
