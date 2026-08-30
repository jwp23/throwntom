package pomodoro

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// downSnapshot is a work phase that began 10 minutes before the daemon came
// back, under a 25-minute work_minutes that has since been edited.
func downSnapshot(start time.Time) Snapshot {
	return Snapshot{
		Engine: engine.Snapshot{
			State:          engine.Work,
			LastPhase:      engine.Work,
			WorkDayStarted: true,
			WorkDate:       start,
		},
		PhaseStartedAt: start,
		PhaseEndAt:     start.Add(25 * time.Minute),
	}
}

// ADR-006: a phase keeps accruing wall-clock time through downtime (2), but
// the duration it is measured against always comes from the current config
// (3). Lengthening work_minutes while the daemon is stopped must therefore
// give the same result as lengthening it while the daemon runs.
func TestRestoreMeasuresElapsedAgainstALengthenedDuration(t *testing.T) {
	start := time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC)
	now := start.Add(10 * time.Minute)
	a := New(50, 5, 15, 4)
	clock := newFakeClock(now)
	a.setClock(clock)

	if err := a.Restore(downSnapshot(start), now); err != nil {
		t.Fatalf(fmtRestore, err)
	}

	if got := a.State(); got != engine.Work {
		t.Fatalf("expected work to resume, got %s", got)
	}
	if got := a.Snapshot().PhaseEndAt.Sub(now); got != 40*time.Minute {
		t.Fatalf("expected 40m left of the new 50m phase, got %s", got)
	}
}

func TestRestoreMeasuresElapsedAgainstAShortenedDuration(t *testing.T) {
	start := time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC)
	now := start.Add(10 * time.Minute)
	a := New(12, 5, 15, 4)
	clock := newFakeClock(now)
	a.setClock(clock)

	if err := a.Restore(downSnapshot(start), now); err != nil {
		t.Fatalf(fmtRestore, err)
	}

	if got := a.Snapshot().PhaseEndAt.Sub(now); got != 2*time.Minute {
		t.Fatalf("expected 2m left of the new 12m phase, got %s", got)
	}
}

// The boundary ADR-006 settles: a duration shorter than the time already
// spent means the phase should already be over.
func TestRestoreEndsAPhaseShorterThanTheElapsedTime(t *testing.T) {
	start := time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC)
	now := start.Add(10 * time.Minute)
	a := New(5, 5, 15, 4)
	clock := newFakeClock(now)
	a.setClock(clock)

	if err := a.Restore(downSnapshot(start), now); err != nil {
		t.Fatalf(fmtRestore, err)
	}

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf(fmtExpectedAwaitingConfirm, got)
	}
	if got := a.Snapshot().Engine.CompletedToday; got != 1 {
		t.Fatalf("expected the ended pomodoro to be counted, got %d", got)
	}
}

// Downtime is not a pause: time spent with the daemon stopped counts, so a
// phase whose new duration ran out during the outage comes back complete.
func TestRestoreCountsDowntimeTowardTheNewDuration(t *testing.T) {
	start := time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC)
	now := start.Add(3 * time.Hour)
	a := New(50, 5, 15, 4)
	clock := newFakeClock(now)
	a.setClock(clock)

	if err := a.Restore(downSnapshot(start), now); err != nil {
		t.Fatalf(fmtRestore, err)
	}

	if got := a.State(); got != engine.AwaitingConfirm {
		t.Fatalf(fmtExpectedAwaitingConfirm, got)
	}
}

// A paused phase is frozen, so its elapsed time is whatever it had spent when
// it was paused — measured, like any other, against the current duration.
func TestRestorePausedPhaseUsesTheCurrentDuration(t *testing.T) {
	start := time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC)
	now := start.Add(2 * time.Hour)
	a := New(50, 5, 15, 4)
	clock := newFakeClock(now)
	a.setClock(clock)
	snap := Snapshot{
		Engine: engine.Snapshot{
			State:          engine.Paused,
			LastPhase:      engine.Work,
			PausedFrom:     engine.Work,
			WorkDayStarted: true,
			WorkDate:       start,
		},
		PausedElapsed:   10 * time.Minute,
		PausedRemaining: 15 * time.Minute,
	}

	if err := a.Restore(snap, now); err != nil {
		t.Fatalf(fmtRestore, err)
	}

	if got := a.State(); got != engine.Paused {
		t.Fatalf("expected the phase to stay paused, got %s", got)
	}
	if got := a.Snapshot().PausedRemaining; got != 40*time.Minute {
		t.Fatalf("expected 40m left of the new 50m phase, got %s", got)
	}
}

// A session with no recorded phase start cannot say how much of the phase was
// spent — a hand-edited or truncated file. Falling back to the stored end
// time keeps the phase running rather than ending it on a guess.
func TestRestoreWithoutAPhaseStartKeepsTheStoredEndTime(t *testing.T) {
	start := time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC)
	now := start.Add(10 * time.Minute)
	a := New(50, 5, 15, 4)
	clock := newFakeClock(now)
	a.setClock(clock)
	snap := downSnapshot(start)
	snap.PhaseStartedAt = time.Time{}

	if err := a.Restore(snap, now); err != nil {
		t.Fatalf(fmtRestore, err)
	}

	if got := a.Snapshot().PhaseEndAt.Sub(now); got != 15*time.Minute {
		t.Fatalf("expected the stored 15m remainder, got %s", got)
	}
}

// The phase start survives a restore, so a session saved after coming back up
// still measures elapsed from when the phase really began.
func TestRestoreKeepsThePhaseStartForLaterSnapshots(t *testing.T) {
	start := time.Date(2026, 8, 29, 9, 0, 0, 0, time.UTC)
	now := start.Add(10 * time.Minute)
	a := New(50, 5, 15, 4)
	clock := newFakeClock(now)
	a.setClock(clock)

	if err := a.Restore(downSnapshot(start), now); err != nil {
		t.Fatalf(fmtRestore, err)
	}

	if got := a.Snapshot().PhaseStartedAt; !got.Equal(start) {
		t.Fatalf("expected the phase start preserved as %s, got %s", start, got)
	}
}
