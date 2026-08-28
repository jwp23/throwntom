package core

import (
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
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
	got := waitForSounds(t, rec, 1)
	settle()
	if got = rec.snapshot(); len(got) != 1 || got[0] != "morning" {
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
	if err := r.suppress(until); err != nil {
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
	if err := r.suppress(clk.Now().Add(time.Minute)); err != nil {
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
	if err := r.suppress(clk.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if err := r.suppress(clk.Now().Add(5 * time.Minute)); err != nil {
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
	if err := r.suppress(clk.Now().Add(time.Minute)); !errors.Is(err, errNoReminder) {
		t.Fatalf("expected errNoReminder, got %v", err)
	}
}

func TestRaiseWhileSuppressedKeepsSnooze(t *testing.T) {
	r, rec, clk := newTestReminder(t)
	r.raise(reminderMorning)
	waitForSounds(t, rec, 1)
	if err := r.suppress(clk.Now().Add(time.Minute)); err != nil {
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
	r.raise(reminderMorning)
	waitForSounds(t, rec, 1)
	r.raise(reminderMorning)
	if count() != 1 {
		t.Fatalf("expected 1 change after raise+repeat, got %d", count())
	}
	if err := r.suppress(clk.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	clk.Advance(time.Minute)
	waitForSounds(t, rec, 2)
	if count() != 3 {
		t.Fatalf("expected suppress and resume to notify (3 total), got %d", count())
	}
	r.cancel()
	if count() != 4 {
		t.Fatalf("expected cancel to notify (4 total), got %d", count())
	}
}

func TestShouldRaiseMorningOncePerDayAndNotWhileSnoozed(t *testing.T) {
	r, rec, clk := newTestReminder(t)
	sched := scheduler.New(config.ScheduleDayTimes(config.Default().Schedule))
	now := clk.Now() // Monday 10:00, after the default 09:15 schedule
	if !r.shouldRaiseMorning(now, sched) {
		t.Fatal("expected first check after schedule time to trigger")
	}
	if r.shouldRaiseMorning(now.Add(time.Minute), sched) {
		t.Fatal("expected second check on the same day not to trigger")
	}
	r.raise(reminderMorning)
	waitForSounds(t, rec, 1)
	if err := r.suppress(now.Add(time.Hour)); err != nil {
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
	if r.shouldRaiseMorning(clk.Now().Add(time.Minute), sched) {
		t.Fatal("expected no trigger after skipToday")
	}
}
