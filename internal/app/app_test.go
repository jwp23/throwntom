package app

import (
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/reminder"
)

// testPolicy keeps the alert bound out of the way of tests that are not about it.
func testPolicy(interval time.Duration) reminder.Policy {
	return reminder.Policy{Interval: interval, MaxAlerts: 1000}
}

const (
	fmtRestore                 = "Restore: %v"
	fmtExpectedAwaitingConfirm = "expected AwaitingConfirm, got %s"
	statusTodayPomodoros1      = "Today: 1"
)

type fakeNotifier struct {
	calls   atomic.Int32
	err     error
	mu      sync.Mutex
	shown   []string
	cleared int
}

func (f *fakeNotifier) PlaySound(string) error {
	f.calls.Add(1)
	return f.err
}

func (f *fakeNotifier) ShowReminder(title, body string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.shown = append(f.shown, title+"|"+body)
	return nil
}

func (f *fakeNotifier) ClearReminder() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.cleared++
	return nil
}

func (f *fakeNotifier) reminders() ([]string, int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.shown...), f.cleared
}

func TestNextStageWhenAwaitingAfterWork(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()
	a.CompletePeriod()
	state, dur := a.NextStage()
	if state != engine.ShortBreak {
		t.Fatalf("expected ShortBreak, got %s", state)
	}
	if dur != 5*time.Minute {
		t.Fatalf("expected 5m duration, got %s", dur)
	}
}

func TestNextStageWhenAwaitingAfterBreak(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()
	a.CompletePeriod()
	a.Confirm()
	a.CompletePeriod()
	state, dur := a.NextStage()
	if state != engine.Work {
		t.Fatalf("expected Work, got %s", state)
	}
	if dur != 25*time.Minute {
		t.Fatalf("expected 25m duration, got %s", dur)
	}
}

func TestNextStageLongBreakBoundary(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()
	for i := 0; i < 3; i++ {
		a.CompletePeriod()
		a.Confirm()
		a.CompletePeriod()
		a.Confirm()
	}
	a.CompletePeriod()
	state, dur := a.NextStage()
	if state != engine.LongBreak {
		t.Fatalf("expected LongBreak, got %s", state)
	}
	if dur != 15*time.Minute {
		t.Fatalf("expected 15m duration, got %s", dur)
	}
}

func TestNextStageOutsideAwaitingConfirm(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	state, dur := a.NextStage()
	if state != engine.Idle {
		t.Fatalf("expected Idle when not awaiting, got %s", state)
	}
	if dur != 0 {
		t.Fatalf("expected zero duration, got %s", dur)
	}
}

func TestStateShowsAwaitingConfirm(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()
	a.CompletePeriod()
	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf(fmtExpectedAwaitingConfirm, got)
	}
}

func TestConfirmStopsReminderLoop(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()
	a.CompletePeriod()
	time.Sleep(70 * time.Millisecond)
	a.Confirm()
	got := n.calls.Load()
	time.Sleep(70 * time.Millisecond)
	if n.calls.Load() != got {
		t.Fatalf("expected reminder loop to stop after confirm")
	}
}

func TestCountdownFormatMMSS(t *testing.T) {
	got := formatRemaining(9*time.Minute + 5*time.Second)
	if got != "09:05" {
		t.Fatalf("expected 09:05, got %s", got)
	}
}

func TestStatusLineShowsPendingWhenAwaitingConfirm(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()
	a.CompletePeriod()
	line := a.StatusLine()
	if !strings.Contains(line, "Confirm to continue") {
		t.Fatalf("expected Confirm to continue line, got %s", line)
	}
}

func TestStatusLineUsesPomodoroLabel(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()
	line := a.StatusLine()
	if !strings.Contains(line, "Cycle: 0/4") {
		t.Fatalf("expected completed-only pomodoro progress, got %s", line)
	}
	if !strings.Contains(line, "Today: 0") {
		t.Fatalf("expected day total count in status line, got %s", line)
	}
	a.CompletePeriod()
	line = a.StatusLine()
	if !strings.Contains(line, "Cycle: 1/4") {
		t.Fatalf("expected done pomodoro progress after completion, got %s", line)
	}
}

func TestStatusLineShowsFullCycleAtLongBreakBoundary(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()

	for i := 0; i < 3; i++ {
		a.CompletePeriod()
		a.Confirm()
		a.CompletePeriod()
		a.Confirm()
	}

	a.CompletePeriod()
	awaiting := a.StatusLine()
	if !strings.Contains(awaiting, "Confirm to continue") {
		t.Fatalf("expected Confirm to continue boundary state, got %s", awaiting)
	}
	if !strings.Contains(awaiting, "Cycle: 4/4") {
		t.Fatalf("expected full-cycle progress at boundary, got %s", awaiting)
	}

	a.Confirm()
	longBreak := a.StatusLine()
	if !strings.Contains(longBreak, "Long break") {
		t.Fatalf("expected Long break after confirming boundary transition, got %s", longBreak)
	}
	if !strings.Contains(longBreak, "Cycle: 4/4") {
		t.Fatalf("expected full-cycle progress during long break, got %s", longBreak)
	}
}

func TestPauseAndResume(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()
	a.Pause()
	if got := a.State(); got != engine.Paused {
		t.Fatalf("expected Paused, got %s", got)
	}
	a.Resume()
	if got := a.State(); got != engine.Work {
		t.Fatalf("expected Work after resume, got %s", got)
	}
}

func TestStopResetsToIdle(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()
	a.Stop()
	if got := a.State(); got != engine.Idle {
		t.Fatalf("expected Idle, got %s", got)
	}
	line := a.StatusLine()
	if !strings.Contains(line, "Idle") {
		t.Fatalf("expected Idle status, got %s", line)
	}
}

func TestStartNewCycleResetsCycleProgressButPreservesDailyTotal(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()
	a.CompletePeriod()
	if !strings.Contains(a.StatusLine(), statusTodayPomodoros1) {
		t.Fatalf("expected daily total before reset, got %s", a.StatusLine())
	}

	a.StartNewCycle()
	line := a.StatusLine()
	if !strings.Contains(line, "Pomodoro") {
		t.Fatalf("expected Pomodoro state after new cycle, got %s", line)
	}
	if !strings.Contains(line, "Cycle: 0/4") {
		t.Fatalf("expected cycle progress reset, got %s", line)
	}
	if !strings.Contains(line, statusTodayPomodoros1) {
		t.Fatalf("expected daily total preserved, got %s", line)
	}
}

func TestRestoreWorkWithTimeRemaining(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	now := time.Now()
	snap := Snapshot{
		Engine: engine.Snapshot{
			State:          engine.Work,
			LastPhase:      engine.Work,
			WorkSessions:   0,
			CompletedToday: 2,
			WorkDayStarted: true,
		},
		PhaseEndAt: now.Add(10 * time.Minute),
	}
	if err := a.Restore(snap, now); err != nil {
		t.Fatalf(fmtRestore, err)
	}
	if got := a.State(); got != engine.Work {
		t.Fatalf("expected Work, got %s", got)
	}
	line := a.StatusLine()
	if !strings.Contains(line, "Today: 2") {
		t.Fatalf("expected completedToday=2, got %s", line)
	}
}

func TestRestoreWorkExpiredTransitionsToAwaitingConfirm(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	now := time.Now()
	snap := Snapshot{
		Engine: engine.Snapshot{
			State:          engine.Work,
			LastPhase:      engine.Work,
			WorkSessions:   0,
			CompletedToday: 0,
			WorkDayStarted: true,
		},
		PhaseEndAt: now.Add(-1 * time.Second),
	}
	if err := a.Restore(snap, now); err != nil {
		t.Fatalf(fmtRestore, err)
	}
	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf(fmtExpectedAwaitingConfirm, got)
	}
}

func TestRestorePausedPreservesRemaining(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	snap := Snapshot{
		Engine: engine.Snapshot{
			State:      engine.Paused,
			LastPhase:  engine.Work,
			PausedFrom: engine.Work,
		},
		PausedRemaining: 12 * time.Minute,
	}
	if err := a.Restore(snap, time.Now()); err != nil {
		t.Fatalf(fmtRestore, err)
	}
	if got := a.State(); got != engine.Paused {
		t.Fatalf("expected Paused, got %s", got)
	}
	a.Resume()
	if got := a.State(); got != engine.Work {
		t.Fatalf("expected Work after resume, got %s", got)
	}
}

func TestRestoreAwaitingConfirmStartsReminder(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	snap := Snapshot{
		Engine: engine.Snapshot{
			State:     engine.AwaitingConfirm,
			LastPhase: engine.Work,
		},
	}
	if err := a.Restore(snap, time.Now()); err != nil {
		t.Fatalf(fmtRestore, err)
	}
	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf(fmtExpectedAwaitingConfirm, got)
	}
	time.Sleep(50 * time.Millisecond)
	if n.calls.Load() == 0 {
		t.Fatal("expected reminder to fire after restoring AwaitingConfirm")
	}
	a.Stop()
}

func TestRestoreIdleIsClean(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	snap := Snapshot{
		Engine: engine.Snapshot{
			State:          engine.Idle,
			CompletedToday: 5,
			WorkDayStarted: true,
		},
	}
	if err := a.Restore(snap, time.Now()); err != nil {
		t.Fatalf(fmtRestore, err)
	}
	if got := a.State(); got != engine.Idle {
		t.Fatalf("expected Idle, got %s", got)
	}
	line := a.StatusLine()
	if !strings.Contains(line, "Today: 5") {
		t.Fatalf("expected completedToday=5 preserved, got %s", line)
	}
}

func TestSnapshotRestoreRoundTrip(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	a.Start()
	a.CompletePeriod()
	a.Confirm()

	snap := a.Snapshot()
	a2 := New(25, 5, 15, 4, testPolicy(20*time.Millisecond), n)
	if err := a2.Restore(snap, time.Now()); err != nil {
		t.Fatalf(fmtRestore, err)
	}
	if got := a2.State(); got != engine.ShortBreak {
		t.Fatalf("expected ShortBreak after restore, got %s", got)
	}
	line := a2.StatusLine()
	if !strings.Contains(line, statusTodayPomodoros1) {
		t.Fatalf("expected completedToday=1, got %s", line)
	}
	a2.Stop()
}

func TestOnChangeFiresWhenPhaseTimerExpires(t *testing.T) {
	a := New(25, 5, 15, 4, testPolicy(time.Hour), &fakeNotifier{})
	clk := newFakeClock(time.Now())
	a.setClock(clk)
	fired := make(chan struct{}, 4)
	a.SetOnChange(func() { fired <- struct{}{} })

	snap := a.Snapshot()
	snap.Engine.State = engine.Work
	snap.PhaseEndAt = clk.Now().Add(20 * time.Minute)
	if err := a.Restore(snap, clk.Now()); err != nil {
		t.Fatal(err)
	}
	<-fired // Restore itself

	clk.Advance(20 * time.Minute)
	select {
	case <-fired:
	default:
		t.Fatal("expected OnChange when the phase timer expired")
	}
	if a.State() != engine.AwaitingConfirm {
		t.Fatalf("state = %s", a.State())
	}
	a.Stop()
}

func TestStatusLineCountdownFollowsInjectedClock(t *testing.T) {
	a := New(25, 5, 15, 4, testPolicy(time.Hour), &fakeNotifier{})
	clk := newFakeClock(time.Now())
	a.setClock(clk)
	a.Start()

	if line := a.StatusLine(); !strings.Contains(line, "25:00") {
		t.Fatalf("expected a full countdown at start, got %s", line)
	}
	clk.Advance(90 * time.Second)
	if line := a.StatusLine(); !strings.Contains(line, "23:30") {
		t.Fatalf("expected the countdown to follow the clock, got %s", line)
	}
	a.Stop()
}

func TestPauseCapturesRemainingFromInjectedClock(t *testing.T) {
	a := New(25, 5, 15, 4, testPolicy(time.Hour), &fakeNotifier{})
	clk := newFakeClock(time.Now())
	a.setClock(clk)
	a.Start()

	clk.Advance(5 * time.Minute)
	if !a.Pause() {
		t.Fatal("expected Pause to report true during work")
	}
	if got := a.Snapshot().PausedRemaining; got != 20*time.Minute {
		t.Fatalf("expected 20m remaining at pause, got %s", got)
	}

	clk.Advance(time.Hour) // paused time must not count against the phase
	if !a.Resume() {
		t.Fatal("expected Resume to report true when paused")
	}
	if line := a.StatusLine(); !strings.Contains(line, "20:00") {
		t.Fatalf("expected the paused remainder to resume, got %s", line)
	}
	a.Stop()
}

func TestSnoozeRestartsReminderAfterInterval(t *testing.T) {
	n := &fakeNotifier{}
	// A one-hour repeat interval means each reminder loop notifies once, so a
	// second notification can only come from a loop the snooze restarted.
	a := New(25, 5, 15, 4, testPolicy(time.Hour), n)
	clk := newFakeClock(time.Now())
	a.setClock(clk)
	a.Start()
	a.CompletePeriod()
	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf(fmtExpectedAwaitingConfirm, got)
	}

	a.Snooze(10 * time.Minute)
	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf("expected phase unchanged by snooze, got %s", got)
	}
	clk.Advance(10 * time.Minute)
	waitForNotifications(t, n, 2)
	a.Stop()
}

// waitForNotifications waits for the reminder goroutines to deliver want
// notifications. The schedule is deterministic; only goroutine start-up is not.
func waitForNotifications(t *testing.T, n *fakeNotifier, want int32) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if n.calls.Load() >= want {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("expected %d reminder notifications, got %d", want, n.calls.Load())
}

func TestOnChangeFiresOnVerbs(t *testing.T) {
	a := New(25, 5, 15, 4, testPolicy(time.Hour), &fakeNotifier{})
	count := 0
	a.SetOnChange(func() { count++ })
	a.Start()
	a.Pause()
	a.Resume()
	a.Stop()
	if count != 4 {
		t.Fatalf("expected 4 change callbacks, got %d", count)
	}
}

func TestAdvanceDayDoesNotNotifyWithoutRollover(t *testing.T) {
	a := New(25, 5, 15, 4, testPolicy(time.Hour), &fakeNotifier{})
	now := time.Now()
	count := 0
	a.SetOnChange(func() { count++ })

	a.AdvanceDay(now) // records the first work date, nothing observable changes
	a.AdvanceDay(now.Add(time.Minute))
	if count != 0 {
		t.Fatalf("expected no change callbacks within the same day, got %d", count)
	}
}

func TestAdvanceDayNotifiesOnRollover(t *testing.T) {
	a := New(25, 5, 15, 4, testPolicy(time.Hour), &fakeNotifier{})
	yesterday := time.Now().Add(-24 * time.Hour)
	snap := a.Snapshot()
	snap.Engine.WorkDate = yesterday
	snap.Engine.CompletedToday = 2
	if err := a.Restore(snap, time.Now()); err != nil {
		t.Fatalf(fmtRestore, err)
	}
	count := 0
	a.SetOnChange(func() { count++ })

	a.AdvanceDay(time.Now())
	if count != 1 {
		t.Fatalf("expected 1 change callback after the day rolled over, got %d", count)
	}
	if got := a.Snapshot().Engine.CompletedToday; got != 0 {
		t.Fatalf("expected completedToday reset, got %d", got)
	}
}

func TestPauseReportsRefusalWhenIdle(t *testing.T) {
	a := New(25, 5, 15, 4, testPolicy(time.Hour), &fakeNotifier{})
	if a.Pause() {
		t.Fatal("expected Pause to report false when idle")
	}
	a.Start()
	if !a.Pause() {
		t.Fatal("expected Pause to report true during work")
	}
	if !a.Resume() {
		t.Fatal("expected Resume to report true when paused")
	}
	if a.Resume() {
		t.Fatal("expected Resume to report false when not paused")
	}
	a.Stop()
}

func TestRefusedPauseAndResumeDoNotNotify(t *testing.T) {
	a := New(25, 5, 15, 4, testPolicy(time.Hour), &fakeNotifier{})
	count := 0
	a.SetOnChange(func() { count++ })

	if a.Pause() {
		t.Fatal("expected Pause to report false when idle")
	}
	if a.Resume() {
		t.Fatal("expected Resume to report false when idle")
	}
	if count != 0 {
		t.Fatalf("expected no change callbacks for refused verbs, got %d", count)
	}

	a.Start()
	if !a.Pause() {
		t.Fatal("expected Pause to report true during work")
	}
	if count != 2 {
		t.Fatalf("expected 2 change callbacks after start and pause, got %d", count)
	}
	a.Stop()
}

// waitFor polls until cond holds, for reminder work that runs off the App lock.
func waitFor(t *testing.T, what string, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if cond() {
			return
		}
		time.Sleep(2 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for %s", what)
}

func TestReminderPostsAnActionableAlertNamingTheNextPhase(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(time.Hour), n)
	a.Start()
	a.CompletePeriod()

	waitFor(t, "the short-break alert", func() bool {
		shown, _ := n.reminders()
		return len(shown) == 1 && shown[0] == "Throwntom|Ready for a short break"
	})
	if _, cleared := n.reminders(); cleared != 0 {
		t.Fatalf("expected no withdrawal yet, got %d", cleared)
	}
}

func TestConfirmWithdrawsTheActionableAlert(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, testPolicy(time.Hour), n)
	a.Start()
	a.CompletePeriod()
	a.Confirm()

	waitFor(t, "the alert to be withdrawn", func() bool {
		_, cleared := n.reminders()
		return cleared == 1
	})
}

func TestReminderThatRunsOutOfAlertsStaysOnScreen(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, reminder.Policy{Interval: 5 * time.Millisecond, MaxAlerts: 2}, n)
	a.Start()
	a.CompletePeriod()

	waitFor(t, "the reminder to run out of alerts", func() bool { return n.calls.Load() == 2 })
	time.Sleep(50 * time.Millisecond)
	if _, cleared := n.reminders(); cleared != 0 {
		t.Fatalf("expected an exhausted reminder to stay posted, got %d withdrawals", cleared)
	}
}

func TestReminderStopsAtItsAlertBound(t *testing.T) {
	n := &fakeNotifier{}
	a := New(25, 5, 15, 4, reminder.Policy{Interval: 5 * time.Millisecond, MaxAlerts: 3}, n)
	a.Start()
	a.CompletePeriod()

	time.Sleep(150 * time.Millisecond)
	if got := n.calls.Load(); got != 3 {
		t.Fatalf("expected the reminder to stop after 3 alerts, got %d", got)
	}
}
