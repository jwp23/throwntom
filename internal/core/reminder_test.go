package core

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/pomodoro"
	"github.com/jwp23/throwntom/v3/internal/reminder"
)

// mondayAt returns a clock set to Monday 2 March 2026 at the given hour, on
// either side of the default 09:15 schedule.
func mondayAt(hour, minute int) *fakeClock {
	return newFakeClock(time.Date(2026, 3, 2, hour, minute, 0, 0, time.UTC))
}

func startedCore(t *testing.T, cfg config.Config, clk *fakeClock) *Core {
	t.Helper()
	c := newCore(cfg, noopNotifier{})
	c.setClock(clk)
	ctx, cancel := context.WithCancel(context.Background())
	c.Start(ctx)
	t.Cleanup(func() { cancel(); c.Stop() })
	return c
}

func TestStartRaisesMorningWhenPendingAndIdle(t *testing.T) {
	c := startedCore(t, config.Default(), mondayAt(10, 0))
	if c.reminder.outstanding() != reminderMorning {
		t.Fatal("expected morning reminder after start with morningPending=true and idle timer")
	}
}

func TestStartSkipsMorningWhenNotPending(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := startedCore(t, cfg, mondayAt(10, 0))
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected no reminder when morningPending=false")
	}
}

func TestStartSkipsMorningWhenTimerNotIdle(t *testing.T) {
	c := newCore(config.Default(), noopNotifier{})
	c.setClock(mondayAt(10, 0))
	c.execute(cmdStart)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c.Start(ctx)
	defer c.Stop()
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected no morning reminder when timer is not idle")
	}
}

func TestStartSkipsMorningBeforeScheduledTime(t *testing.T) {
	c := startedCore(t, config.Default(), mondayAt(8, 0))
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected no morning reminder before scheduled time")
	}
}

func TestMorningSnoozeKeepsPendingAndResumesAtDeadline(t *testing.T) {
	clk := mondayAt(10, 0)
	c := startedCore(t, config.Default(), clk)
	result := c.execute("snooze 10m")
	if result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}
	if !strings.Contains(result.message, "morning reminder snoozed") {
		t.Fatalf("expected morning snooze message, got %q", result.message)
	}
	_, _, pending := c.Status()
	if !pending {
		t.Fatal("expected morning_pending to stay true during a snooze")
	}
	if until, ok := c.reminder.snoozeDeadline(); !ok || !until.Equal(clk.Now().Add(10*time.Minute)) {
		t.Fatalf("expected deadline 10m ahead, got %v %v", until, ok)
	}
	clk.Advance(10 * time.Minute)
	if _, ok := c.reminder.snoozeDeadline(); ok {
		t.Fatal("expected snooze cleared at its deadline")
	}
	if c.reminder.outstanding() != reminderMorning {
		t.Fatal("expected morning reminder still outstanding after resume")
	}
}

func TestStartDuringMorningSnoozeCancelsIt(t *testing.T) {
	clk := mondayAt(10, 0)
	c := startedCore(t, config.Default(), clk)
	if result := c.execute("snooze 10m"); result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}
	c.execute(cmdStart)
	clk.Advance(10 * time.Minute)
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected no reminder after start during a snooze")
	}
	if _, ok := c.reminder.snoozeDeadline(); ok {
		t.Fatal("expected deadline cleared by start")
	}
}

func TestSnoozeWithNothingOutstandingIsRefused(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := startedCore(t, cfg, mondayAt(10, 0))
	result := c.execute("snooze 5m")
	if !errors.Is(result.err, errNoReminder) {
		t.Fatalf("expected errNoReminder, got %v", result.err)
	}
	if classifyError(result.err) != ErrorRefused {
		t.Fatal("expected a refusal, not a usage error")
	}
}

func TestSnoozeRejectsNonPositiveDuration(t *testing.T) {
	c := startedCore(t, config.Default(), mondayAt(10, 0))
	for _, arg := range []string{"0", "-5m"} {
		result := c.execute("snooze " + arg)
		if result.err == nil || classifyError(result.err) != ErrorUsage {
			t.Fatalf("snooze %s: expected usage error, got %v", arg, result.err)
		}
	}
}

func TestSkipTodayCancelsMorningReminder(t *testing.T) {
	c := startedCore(t, config.Default(), mondayAt(10, 0))
	c.execute("skip-today")
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected skip-today to cancel the morning reminder")
	}
	_, _, pending := c.Status()
	if pending {
		t.Fatal("expected morning_pending false after skip-today")
	}
}

func TestScheduleTickRaisesMorningOnce(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.setClock(mondayAt(9, 15))
	c.tickMorning()
	if c.reminder.outstanding() != reminderMorning {
		t.Fatal("expected the schedule tick to raise the morning reminder")
	}
	c.reminder.cancel()
	c.tickMorning()
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected the schedule not to fire twice in one day")
	}
}

func TestTickMorningHoldsCoreLock(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.setClock(mondayAt(9, 15))

	c.mu.Lock()
	go c.tickMorning()
	settle()
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected no raise while the core lock is held")
	}
	c.mu.Unlock()

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if c.reminder.outstanding() == reminderMorning {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("expected the morning reminder to raise once the core lock was released")
}

func TestScheduleTickIgnoresBusyTimer(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.setClock(mondayAt(9, 15))
	c.execute(cmdStart)
	c.tickMorning()
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected no morning reminder while a pomodoro runs")
	}
	c.timer.Stop()
}

// TestStopStopsScheduleTick shows that Stop ends the schedule tick itself,
// rather than relying on the caller to cancel ctx first: Start is handed a
// ctx that is never cancelled, so the only thing that can end the tick is
// Stop.
func TestStopStopsScheduleTick(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.setClock(mondayAt(9, 15))
	c.Start(context.Background())
	c.Stop()

	time.Sleep(1200 * time.Millisecond)
	if c.reminder.outstanding() == reminderMorning {
		c.reminder.cancel()
		t.Fatal("expected no morning reminder to raise after Stop")
	}
}

// TestStartTwicePanics shows that a second Start is a loud programming
// error rather than silent corruption: without a guard it replaces
// stopSchedule and scheduleDone out from under the first schedule goroutine,
// orphaning it since Stop can no longer reach it.
func TestStartTwicePanics(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.setClock(mondayAt(9, 15))
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c.Start(ctx)
	defer c.Stop()

	defer func() {
		if recover() == nil {
			t.Fatal("expected second Start to panic")
		}
	}()
	c.Start(ctx)
}

// awaitingCore returns a started core sitting at awaiting_confirm with a
// recorder on the sound, the morning reminder out of the way.
func awaitingCore(t *testing.T) (*Core, *soundRecorder, *fakeClock) {
	t.Helper()
	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.RepeatSecs = 3600
	cfg.RepeatLimitSecs = 0
	rec := &soundRecorder{}
	c := newCore(cfg, rec)
	clk := mondayAt(10, 0)
	c.setClock(clk)
	ctx, cancel := context.WithCancel(context.Background())
	c.Start(ctx)
	t.Cleanup(func() { cancel(); c.Stop() })
	c.execute(cmdStart)
	c.timer.CompletePeriod()
	return c, rec, clk
}

func TestPeriodCompletionRaisesCycleReminderOnce(t *testing.T) {
	c, rec, _ := awaitingCore(t)
	waitForSounds(t, rec, 1)
	settle()
	if got := rec.snapshot(); len(got) != 1 || got[0] != "default" {
		t.Fatalf("expected one cycle ring, got %v", got)
	}
	if c.reminder.outstanding() != reminderCycle {
		t.Fatal("expected cycle reminder outstanding at awaiting_confirm")
	}
}

func TestConfirmCancelsCycleReminder(t *testing.T) {
	c, rec, clk := awaitingCore(t)
	waitForSounds(t, rec, 1)
	if result := c.execute("snooze 5m"); result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}
	c.execute("confirm")
	clk.Advance(5 * time.Minute)
	settle()
	if got := rec.snapshot(); len(got) != 1 {
		t.Fatalf("expected no ring after confirm, got %v", got)
	}
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected nothing outstanding after confirm")
	}
}

func TestCycleSnoozePublishesDeadlineThenClearsAndRings(t *testing.T) {
	c, rec, clk := awaitingCore(t)
	waitForSounds(t, rec, 1)
	result := c.execute("snooze 5m")
	if result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}
	if !strings.Contains(result.message, "cycle reminder snoozed") {
		t.Fatalf("expected cycle snooze message, got %q", result.message)
	}
	s := c.State()
	if s.SnoozeUntil == nil || !s.SnoozeUntil.Equal(clk.Now().Add(5*time.Minute)) {
		t.Fatalf("expected snooze_until 5m ahead, got %v", s.SnoozeUntil)
	}
	clk.Advance(5 * time.Minute)
	waitForSounds(t, rec, 2)
	if s := c.State(); s.SnoozeUntil != nil || s.State != engine.AwaitingConfirm {
		t.Fatalf("expected snooze_until null at awaiting_confirm after expiry, got %+v", s)
	}
}

func TestRestoreIntoAwaitingConfirmRaisesOnce(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.RepeatSecs = 3600
	rec := &soundRecorder{}
	c := newCore(cfg, rec)
	c.setClock(mondayAt(10, 0))
	snap := pomodoro.Snapshot{Engine: engine.Snapshot{State: engine.AwaitingConfirm, LastPhase: engine.Work, WorkDayStarted: true}}
	c.mu.Lock()
	err := c.timer.Restore(snap, c.now())
	c.mu.Unlock()
	if err != nil {
		t.Fatal(err)
	}
	defer c.Stop()
	waitForSounds(t, rec, 1)
	settle()
	if got := rec.snapshot(); len(got) != 1 {
		t.Fatalf("expected exactly one ring after restore, got %v", got)
	}
}

func TestStartWithFocusPromptSilencesMorningReminder(t *testing.T) {
	dir := t.TempDir()
	cfg := config.Default()
	cfg.RepeatSecs = 3600
	rec := &soundRecorder{}
	c := newCore(cfg, rec)
	if err := c.initTasks(filepath.Join(dir, "tasks.json")); err != nil {
		t.Fatal(err)
	}
	c.setClock(mondayAt(10, 0))
	ctx, cancel := context.WithCancel(context.Background())
	c.Start(ctx)
	t.Cleanup(func() { cancel(); c.Stop() })
	waitForSounds(t, rec, 1)
	result := c.execute(cmdStart)
	if result.err != nil {
		t.Fatal(result.err)
	}
	if !c.pendingFocusPrompt {
		t.Fatal("expected start to enter the focus prompt")
	}
	if c.reminder.outstanding() != reminderNone {
		t.Fatal("expected the morning reminder cancelled before the focus prompt")
	}
}

func TestMorningReminderPolicyComesFromConfig(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.RepeatSecs = 30
	cfg.RepeatLimitSecs = 120
	c := newCore(cfg, noopNotifier{})
	want := reminder.Policy{Interval: 30 * time.Second, MaxAlerts: 5}
	if c.reminder.policy != want {
		t.Fatalf("expected %+v, got %+v", want, c.reminder.policy)
	}
}
