package core

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/pomodoro"
	"github.com/jwp23/throwntom/v3/internal/session"
	"github.com/jwp23/throwntom/v3/internal/task"
)

type countingNotifier struct {
	calls atomic.Int64
}

func (n *countingNotifier) PlaySound(string) error {
	n.calls.Add(1)
	return nil
}

func TestSaveSessionWritesValidJSON(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	defer c.Stop()
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
	defer c.Stop()
	c.execute(cmdStart)
	c.timer.CompletePeriod()
	c.saveSession()

	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = sessPath
	defer c2.Stop()
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
	defer c.Stop()
	if err := c.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	status, _, _ := c.Status()
	if !strings.Contains(status, "Idle") {
		t.Fatalf("expected Idle for different-day session, got %s", status)
	}
}

func TestLoadSessionDiscardsInternallyInconsistentState(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	// The exact 2026-08-27 incident snapshot: awaiting_confirm after a break
	// that, per completed_today and work_day_started, never happened.
	data := session.Data{
		SavedAt: time.Now(),
		Timer: pomodoro.Snapshot{
			Engine: engine.Snapshot{
				State:          engine.AwaitingConfirm,
				LastPhase:      engine.ShortBreak,
				CompletedToday: 0,
				WorkDayStarted: false,
			},
		},
	}
	if err := session.Save(sessPath, data); err != nil {
		t.Fatal(err)
	}

	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.RepeatSecs = 1
	n := &countingNotifier{}
	c := newCore(cfg, n)
	c.sessionPath = sessPath
	var warnings bytes.Buffer
	c.setWarnOut(&warnings)
	defer c.Stop()
	if err := c.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	status, _, _ := c.Status()
	if !strings.Contains(status, "Idle") {
		t.Fatalf("expected Idle for internally inconsistent session, got %s", status)
	}
	wantWarning := "warning: discarding inconsistent session: work_day_started is false but state/last_phase is not idle\n"
	if got := warnings.String(); got != wantWarning {
		t.Fatalf("expected discard warning %q, got %q", wantWarning, got)
	}
	time.Sleep(1200 * time.Millisecond)
	if got := n.calls.Load(); got != 0 {
		t.Fatalf("expected no reminder to fire for a discarded session, got %d calls", got)
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
	defer c.Stop()
	c.tasks = store
	c.execute(cmdStart)
	c.setFocused([]task.Task{t3, t1})
	c.saveSession()

	store2, _ := task.NewFileStore(tasksPath)
	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = sessPath
	defer c2.Stop()
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
	defer c.Stop()
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
	defer c.Stop()

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
	defer c.Stop()
	c.execute(cmdStart)
	c.saveSession()

	cfg2 := config.Default()
	c2 := newCore(cfg2, noopNotifier{})
	c2.sessionPath = sessPath
	defer c2.Stop()
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	dayKey := time.Now().Format("2006-01-02")
	c2.reminder.mu.Lock()
	gotDay := c2.reminder.lastTriggerDay
	c2.reminder.mu.Unlock()
	if gotDay != dayKey {
		t.Fatalf("expected lastTriggerDay=%s, got %s", dayKey, gotDay)
	}
}

func TestSaveLoadExpiredTimerTransitionsToAwaitingConfirm(t *testing.T) {
	dir := t.TempDir()
	savedPath := filepath.Join(dir, testSessionFile)
	restoredPath := filepath.Join(dir, "restored-session.json")

	cfg := config.Default()
	cfg.MorningReminderPending = false
	// Both cores run on an injected clock pinned to midday so the save and the
	// restore always fall on the same calendar day (loadSession discards a
	// session saved on a different day); a real wall clock near midnight
	// would otherwise make the restore look like a new day.
	savedAt := time.Date(2026, 3, 2, 12, 0, 0, 0, time.Local)
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = savedPath
	c.setNow(func() time.Time { return savedAt })
	defer c.Stop()
	c.execute(cmdStart)
	c.saveSession()

	data, err := session.Load(savedPath)
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	// now is deliberately offset from the save clock: PhaseEndAt sits 5s
	// before it, but over an hour in the future relative to the save. If the
	// expiry check used the real clock instead of the injected one, PhaseEndAt
	// would look not-yet-expired and this test would fail — proving Restore
	// honors the injected clock rather than depending on real elapsed time
	// between save and restore.
	now := savedAt.Add(time.Hour)
	data.Timer.PhaseEndAt = now.Add(-5 * time.Second)
	// The phase start has to move with the end it belongs to: Restore measures
	// elapsed from the start against the configured duration, so a start left
	// on the real clock would describe a phase that never ran.
	data.Timer.PhaseStartedAt = data.Timer.PhaseEndAt.Add(-time.Duration(cfg.Pomodoro.WorkMinutes) * time.Minute)
	// The doctored session gets a file of its own. The first core is still
	// alive and every change it publishes rewrites its own session file
	// asynchronously, which would otherwise restore the live, unexpired phase
	// end over the expired one this test wrote.
	if err := session.Save(restoredPath, data); err != nil {
		t.Fatalf("Save: %v", err)
	}

	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = restoredPath
	c2.setNow(func() time.Time { return now })
	defer c2.Stop()
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	state := c2.timer.State()
	if state != engine.AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm for expired timer, got %s", state)
	}
	c2.timer.Stop()
}

func TestSaveLoadPausedPreservesRemainingDuration(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	defer c.Stop()
	c.execute(cmdStart)
	c.execute("pause")
	c.saveSession()

	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = sessPath
	defer c2.Stop()
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	state := c2.timer.State()
	if state != engine.Paused {
		t.Fatalf("expected Paused, got %s", state)
	}
	c2.execute("resume")
	state = c2.timer.State()
	if state != engine.Work {
		t.Fatalf("expected Work after resume, got %s", state)
	}
	c2.timer.Stop()
}

func TestSaveLoadCompletedTodayPersists(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	defer c.Stop()

	c.execute(cmdStart)
	for i := 0; i < 3; i++ {
		c.timer.CompletePeriod()
		c.execute("confirm")
		c.timer.CompletePeriod()
		c.execute("confirm")
	}

	status, _, _ := c.Status()
	if !strings.Contains(status, "Today: 3") {
		t.Fatalf("expected Today: 3 before save, got %s", status)
	}
	c.saveSession()

	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = sessPath
	defer c2.Stop()
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	status2, _, _ := c2.Status()
	if !strings.Contains(status2, "Today: 3") {
		t.Fatalf("expected Today: 3 after load, got %s", status2)
	}
	c2.timer.Stop()
}

func TestLoadSessionIntoAwaitingConfirmKeepsCycleReminder(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	savedAt := mondayAt(10, 0).Now()
	data := session.Data{
		SavedAt: savedAt,
		Timer: pomodoro.Snapshot{
			Engine: engine.Snapshot{State: engine.AwaitingConfirm, LastPhase: engine.Work, WorkDayStarted: true},
		},
	}
	if err := session.Save(sessPath, data); err != nil {
		t.Fatal(err)
	}

	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.RepeatSecs = 3600
	rec := &soundRecorder{}
	c := newCore(cfg, rec)
	c.setClock(mondayAt(10, 0))
	c.sessionPath = sessPath
	defer c.Stop()
	if err := c.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	if c.reminder.outstanding() != reminderCycle {
		t.Fatal("expected the cycle reminder to survive a restore into awaiting_confirm")
	}
	waitForSounds(t, rec, 1)
	morning := mondayAt(9, 15).Now()
	if c.reminder.shouldRaiseMorning(morning, c.scheduler.ShouldTrigger(morning)) {
		t.Fatal("expected the morning reminder to still be marked owed for today")
	}
}

func TestSessionSavedAfterMidnightResetsOnReload(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)
	cfg := config.Default()
	cfg.MorningReminderPending = false

	yesterday := time.Date(2026, 3, 5, 17, 0, 0, 0, time.Local)
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	defer c.Stop()
	c.setNow(func() time.Time { return yesterday })

	c.Execute(cmdStart)
	c.timer.CompletePeriod()
	c.Execute("pause")

	afterMidnight := time.Date(2026, 3, 6, 0, 5, 0, 0, time.Local)
	c.setNow(func() time.Time { return afterMidnight })
	c.Stop()

	today := time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)
	c2 := newCore(cfg, noopNotifier{})
	c2.sessionPath = sessPath
	defer c2.Stop()
	c2.setNow(func() time.Time { return today })
	var warnings bytes.Buffer
	c2.setWarnOut(&warnings)
	if err := c2.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	// Stop's AdvanceDay rolled the saved snapshot into the new day before it
	// was written: that clears work_day_started and last_phase but leaves
	// state at awaiting_confirm, which Invalid() rejects. The reload discards
	// the session outright rather than performing a live reset, which is why
	// today's count below comes back zero.
	wantWarning := "warning: discarding inconsistent session: work_day_started is false but state/last_phase is not idle\n"
	if got := warnings.String(); got != wantWarning {
		t.Fatalf("expected discard warning %q, got %q", wantWarning, got)
	}

	status, _, _ := c2.Status()
	if !strings.Contains(status, statusTodayPomodoros0) {
		t.Fatalf("expected today's pomodoros=0 after midnight reload, got %s", status)
	}
}

// "No more reminders today" has to outlive the daemon, or stopping and
// starting the service resurrects the reminders the user just dismissed for
// the day. The engine is idle after skip-today, so only day_ended says so.
func TestLoadSessionIntoAnEndedDayOwesNoMorningReminder(t *testing.T) {
	dir := t.TempDir()
	sessPath := filepath.Join(dir, testSessionFile)

	data := session.Data{
		SavedAt: mondayAt(17, 0).Now(),
		Timer: pomodoro.Snapshot{
			Engine: engine.Snapshot{State: engine.Idle, LastPhase: engine.Idle, DayEnded: true},
		},
	}
	if err := session.Save(sessPath, data); err != nil {
		t.Fatal(err)
	}

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.setClock(mondayAt(17, 0))
	c.sessionPath = sessPath
	defer c.Stop()
	if err := c.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}

	if !c.State().DayEnded {
		t.Fatal("expected the ended day to survive the restore")
	}
	morning := mondayAt(9, 15).Now()
	if c.reminder.shouldRaiseMorning(morning, c.scheduler.ShouldTrigger(morning)) {
		t.Fatal("expected no morning reminder owed on a day the user ended")
	}
}
