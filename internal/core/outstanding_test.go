package core

import (
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/notifier"
	"github.com/jwp23/throwntom/v3/internal/reminder"
	"github.com/jwp23/throwntom/v3/internal/scheduler"
)

// soundRecorder records which sound each ring asked for.
type soundRecorder struct {
	mu    sync.Mutex
	names []string
}

func (s *soundRecorder) PlaySound(name string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.names = append(s.names, name)
	return nil
}

func (s *soundRecorder) snapshot() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.names...)
}

// waitForSounds waits for the loop goroutine to deliver want rings. The
// schedule is deterministic; only goroutine start-up is not.
func waitForSounds(t *testing.T, s *soundRecorder, want int) []string {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if got := s.snapshot(); len(got) >= want {
			return got
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatalf("expected %d rings, got %v", want, s.snapshot())
	return nil
}

// settle gives a loop goroutine time to ring if it wrongly would.
func settle() { time.Sleep(20 * time.Millisecond) }

// onePerRaise makes each loop ring exactly once, so every ring in a test is
// attributable to one raise or resume.
var onePerRaise = reminder.Policy{Interval: time.Hour, MaxAlerts: 1}

func newTestReminder(t *testing.T) (*outstandingReminder, *soundRecorder, *fakeClock) {
	t.Helper()
	rec := &soundRecorder{}
	clk := newFakeClock(time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local))
	r := newOutstandingReminder(onePerRaise, rec)
	r.now = clk.Now
	r.after = clk.After
	t.Cleanup(r.cancel)
	return r, rec, clk
}

func TestRaiseRingsOncePerKindAndIsIdempotent(t *testing.T) {
	r, rec, _ := newTestReminder(t)
	r.raise(reminderMorning)
	r.raise(reminderMorning)
	waitForSounds(t, rec, 1)
	settle()
	if got := rec.snapshot(); len(got) != 1 || got[0] != "morning" {
		t.Fatalf("expected one morning ring, got %v", got)
	}
	if r.outstanding() != reminderMorning {
		t.Fatalf("expected morning outstanding, got %v", r.outstanding())
	}
}

func TestRaiseOtherKindReplaces(t *testing.T) {
	r, rec, _ := newTestReminder(t)
	r.raise(reminderMorning)
	waitForSounds(t, rec, 1)
	r.raise(reminderCycle)
	got := waitForSounds(t, rec, 2)
	if got[1] != "default" || r.outstanding() != reminderCycle {
		t.Fatalf("expected cycle ring after morning, got %v / %v", got, r.outstanding())
	}
}

func TestSuppressThenResumeRingsAgainAtDeadline(t *testing.T) {
	r, rec, clk := newTestReminder(t)
	r.raise(reminderCycle)
	waitForSounds(t, rec, 1)
	until := clk.Now().Add(10 * time.Minute)
	if _, err := r.suppress(until); err != nil {
		t.Fatal(err)
	}
	if got, ok := r.snoozeDeadline(); !ok || !got.Equal(until) {
		t.Fatalf("expected deadline %v, got %v %v", until, got, ok)
	}
	clk.Advance(9 * time.Minute)
	settle()
	if got := rec.snapshot(); len(got) != 1 {
		t.Fatalf("rang before the deadline: %v", got)
	}
	clk.Advance(time.Minute)
	waitForSounds(t, rec, 2)
	if _, ok := r.snoozeDeadline(); ok {
		t.Fatal("expected deadline cleared after resume")
	}
	if r.outstanding() != reminderCycle {
		t.Fatal("expected cycle reminder still outstanding after resume")
	}
}

func TestCancelDuringSnoozeLeavesDeadlineInert(t *testing.T) {
	r, rec, clk := newTestReminder(t)
	r.raise(reminderMorning)
	waitForSounds(t, rec, 1)
	if _, err := r.suppress(clk.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	r.cancel()
	clk.Advance(2 * time.Minute)
	settle()
	if got := rec.snapshot(); len(got) != 1 {
		t.Fatalf("expected no ring after cancel, got %v", got)
	}
	if r.outstanding() != reminderNone {
		t.Fatal("expected nothing outstanding after cancel")
	}
	if _, ok := r.snoozeDeadline(); ok {
		t.Fatal("expected no deadline after cancel")
	}
}

func TestSecondSuppressReplacesDeadline(t *testing.T) {
	r, rec, clk := newTestReminder(t)
	r.raise(reminderCycle)
	waitForSounds(t, rec, 1)
	if _, err := r.suppress(clk.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if _, err := r.suppress(clk.Now().Add(5 * time.Minute)); err != nil {
		t.Fatal(err)
	}
	clk.Advance(2 * time.Minute)
	settle()
	if got := rec.snapshot(); len(got) != 1 {
		t.Fatalf("first deadline should have been replaced, got %v", got)
	}
	clk.Advance(3 * time.Minute)
	waitForSounds(t, rec, 2)
}

func TestSuppressWithNothingOutstandingIsRefused(t *testing.T) {
	r, _, clk := newTestReminder(t)
	if _, err := r.suppress(clk.Now().Add(time.Minute)); !errors.Is(err, errNoReminder) {
		t.Fatalf("expected errNoReminder, got %v", err)
	}
}

func TestRaiseWhileSuppressedKeepsSnooze(t *testing.T) {
	r, rec, clk := newTestReminder(t)
	r.raise(reminderMorning)
	waitForSounds(t, rec, 1)
	if _, err := r.suppress(clk.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	r.raise(reminderMorning)
	settle()
	if got := rec.snapshot(); len(got) != 1 {
		t.Fatalf("raise of the snoozed kind must not ring, got %v", got)
	}
	if _, ok := r.snoozeDeadline(); !ok {
		t.Fatal("expected snooze to survive a repeated raise")
	}
}

func TestOnChangeFiresOnlyOnObservableChange(t *testing.T) {
	r, rec, clk := newTestReminder(t)
	var mu sync.Mutex
	changes := 0
	r.onChange = func() { mu.Lock(); changes++; mu.Unlock() }
	count := func() int { mu.Lock(); defer mu.Unlock(); return changes }

	r.cancel()
	if count() != 0 {
		t.Fatal("cancel with nothing outstanding must not notify")
	}
	// A ring is observable in its own right: the daemon plays no sound, so a
	// client hears the repeat only by being told the count moved. Each raise
	// and each resume therefore notifies twice - once for the change of state,
	// once for the ring that change starts.
	r.raise(reminderMorning)
	waitForSounds(t, rec, 1)
	r.raise(reminderMorning)
	if count() != 2 {
		t.Fatalf("expected raise and its ring to notify, and the repeat not to (2), got %d", count())
	}
	if _, err := r.suppress(clk.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	clk.Advance(time.Minute)
	waitForSounds(t, rec, 2)
	if count() != 5 {
		t.Fatalf("expected suppress, resume and the resumed ring to notify (5 total), got %d", count())
	}
	r.cancel()
	if count() != 6 {
		t.Fatalf("expected cancel to notify (6 total), got %d", count())
	}
}

func TestShouldRaiseMorningOncePerDayAndNotWhileSnoozed(t *testing.T) {
	r, rec, _ := newTestReminder(t)
	sched := scheduler.New(config.ScheduleDayTimes(config.Default().Schedule))
	now := time.Date(2026, 3, 2, 9, 15, 0, 0, time.Local) // Monday 09:15, the default schedule
	if !r.shouldRaiseMorning(now, sched) {
		t.Fatal("expected first check at schedule time to trigger")
	}
	if r.shouldRaiseMorning(now.Add(time.Minute), sched) {
		t.Fatal("expected second check on the same day not to trigger")
	}
	r.raise(reminderMorning)
	waitForSounds(t, rec, 1)
	if _, err := r.suppress(now.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	tomorrow := now.Add(24 * time.Hour)
	if r.shouldRaiseMorning(tomorrow, sched) {
		t.Fatal("expected no trigger while snoozed")
	}
}

func TestSkipTodayCancelsAndStampsDay(t *testing.T) {
	r, rec, clk := newTestReminder(t)
	sched := scheduler.New(config.ScheduleDayTimes(config.Default().Schedule))
	r.raise(reminderMorning)
	waitForSounds(t, rec, 1)
	r.skipToday(clk.Now())
	if r.outstanding() != reminderNone {
		t.Fatal("expected skipToday to cancel")
	}
	if r.shouldRaiseMorning(time.Date(2026, 3, 2, 9, 15, 0, 0, time.Local), sched) {
		t.Fatal("expected no trigger after skipToday")
	}
}

// Silencing the daemon must silence only the sound. The state around a
// reminder is what a client reads to raise its own banner, so suppressing
// audio must not suppress a raise, a snooze deadline or a cancel.
func TestSilentNotifierStillDrivesReminderState(t *testing.T) {
	clk := newFakeClock(time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local))
	r := newOutstandingReminder(onePerRaise, notifier.Silent())
	r.now = clk.Now
	r.after = clk.After
	t.Cleanup(r.cancel)

	var mu sync.Mutex
	changes := 0
	r.onChange = func() { mu.Lock(); changes++; mu.Unlock() }
	count := func() int { mu.Lock(); defer mu.Unlock(); return changes }

	r.raise(reminderCycle)
	if r.outstanding() != reminderCycle {
		t.Fatalf("expected cycle outstanding, got %v", r.outstanding())
	}
	until := clk.Now().Add(10 * time.Minute)
	if _, err := r.suppress(until); err != nil {
		t.Fatal(err)
	}
	if got, ok := r.snoozeDeadline(); !ok || !got.Equal(until) {
		t.Fatalf("expected deadline %v published, got %v %v", until, got, ok)
	}
	clk.Advance(10 * time.Minute)
	settle()
	if _, ok := r.snoozeDeadline(); ok {
		t.Fatal("expected the deadline cleared when the snooze ran out")
	}
	r.cancel()
	if r.outstanding() != reminderNone {
		t.Fatal("expected cancel to retire the reminder")
	}
	// Six, not four: the raise and the resume each also ring, and a ring is
	// what a client reads to chime, so it notifies too.
	if count() != 6 {
		t.Fatalf("expected raise, suppress, resume, cancel and two rings to notify, got %d", count())
	}
}

// Joe's requirement, 2026-08-29: the repeated chime is the reminder that
// works, and the daemon no longer plays it. So each ring of the loop has to
// become something a client can see and sound, and the count is that signal.
func TestEachRingRaisesThePublishedCount(t *testing.T) {
	r := newOutstandingReminder(onePerRaise, notifier.Silent())
	t.Cleanup(r.cancel)

	r.raise(reminderCycle)
	settle()
	if got := r.ringCount(); got != 1 {
		t.Fatalf("expected raising to ring once, got %d", got)
	}

	_ = r.ring()
	_ = r.ring()
	if got := r.ringCount(); got != 3 {
		t.Fatalf("expected each ring to raise the count, got %d", got)
	}
}

// A ring is only meaningful while a reminder is outstanding: the count says
// how many chimes this wait has asked for, so retiring the wait starts the
// next one from silence rather than from wherever the last one stopped.
func TestRetiringTheReminderResetsTheRingCount(t *testing.T) {
	r := newOutstandingReminder(onePerRaise, notifier.Silent())
	t.Cleanup(r.cancel)

	r.raise(reminderCycle)
	settle()
	r.cancel()
	if got := r.ringCount(); got != 0 {
		t.Fatalf("expected cancel to reset the count, got %d", got)
	}

	r.raise(reminderMorning)
	settle()
	if got := r.ringCount(); got != 1 {
		t.Fatalf("expected the next wait to start from one, got %d", got)
	}
}

// The client hears the ring by reading state, so the count has to reach it.
func TestRingCountIsPublishedInState(t *testing.T) {
	r := newOutstandingReminder(onePerRaise, notifier.Silent())
	t.Cleanup(r.cancel)

	var mu sync.Mutex
	changes := 0
	r.onChange = func() { mu.Lock(); changes++; mu.Unlock() }

	_ = r.ring()
	mu.Lock()
	got := changes
	mu.Unlock()
	if got != 1 {
		t.Fatalf("expected a ring to notify observers, got %d", got)
	}
}

// The daemon plays no sound (ADR-007): it publishes a ring count and the macOS
// client chimes once per climb. So "a snooze silences the chime" is really "a
// snooze stops the ring count climbing", which is what this pins down.
func TestSnoozeStopsTheRingsAndUnsnoozeStartsThemAgain(t *testing.T) {
	rec := &soundRecorder{}
	clk := newFakeClock(time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local))
	r := newOutstandingReminder(reminder.Policy{Interval: time.Millisecond, MaxAlerts: 100}, rec)
	r.now = clk.Now
	r.after = clk.After
	t.Cleanup(r.cancel)

	r.raise(reminderMorning)
	waitForSounds(t, rec, 3)

	if _, err := r.suppress(clk.Now().Add(10 * time.Minute)); err != nil {
		t.Fatalf("suppress: %v", err)
	}
	settle()
	quiet := r.ringCount()
	settle()
	if got := r.ringCount(); got != quiet {
		t.Fatalf("a snooze must stop the rings: count went %d -> %d", quiet, got)
	}

	// The count is not reset by the snooze, so a client that has heard n rings
	// does not hear them replayed when the snooze ends.
	if _, err := r.unsuppress(); err != nil {
		t.Fatalf("unsuppress: %v", err)
	}
	waitForSounds(t, rec, quiet+1)
	if got := r.ringCount(); got <= quiet {
		t.Fatalf("ending the snooze must ring again: count stuck at %d", got)
	}
}
