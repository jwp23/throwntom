package pomodoro

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// pausedFor starts a timer with the given threshold, pauses it and moves the
// clock on by elapsed, returning the timer and its clock.
func pausedFor(t *testing.T, threshold, elapsed time.Duration) (*Timer, *fakeClock) {
	t.Helper()
	a := New(25, 5, 15, 4)
	clk := newFakeClock(time.Date(2026, 9, 3, 10, 0, 0, 0, time.UTC))
	a.setClock(clk)
	a.SetPausedTooLongAfter(threshold)
	a.Start()
	if !a.Pause() {
		t.Fatal("expected the running phase to pause")
	}
	clk.Advance(elapsed)
	return a, clk
}

func TestAPauseIsNotTooLongBeforeTheThreshold(t *testing.T) {
	a, _ := pausedFor(t, 10*time.Minute, 10*time.Minute-time.Second)
	if a.PausedTooLong() {
		t.Fatal("a pause one second short of the threshold is not too long yet")
	}
}

func TestAPauseIsTooLongOnceTheThresholdPasses(t *testing.T) {
	a, _ := pausedFor(t, 10*time.Minute, 10*time.Minute)
	if !a.PausedTooLong() {
		t.Fatal("a pause that reached the threshold is too long")
	}
}

// The threshold passing changes nothing a verb reports, so without a change
// of its own no client ever hears about it.
func TestCrossingTheThresholdPublishesTheChange(t *testing.T) {
	a, clk := pausedFor(t, 10*time.Minute, 0)
	changes := make(chan struct{}, 4)
	a.SetOnChange(func() { changes <- struct{}{} })

	clk.Advance(10 * time.Minute)

	select {
	case <-changes:
	default:
		t.Fatal("crossing the threshold published nothing")
	}
}

func TestResumingBeforeTheThresholdNeverReportsTooLong(t *testing.T) {
	a, clk := pausedFor(t, 10*time.Minute, 5*time.Minute)
	changes := make(chan struct{}, 4)
	if !a.Resume() {
		t.Fatal("expected the paused phase to resume")
	}
	a.SetOnChange(func() { changes <- struct{}{} })

	clk.Advance(10 * time.Minute)

	if a.PausedTooLong() {
		t.Fatal("a pause that was resumed in time is never too long")
	}
	select {
	case <-changes:
		t.Fatal("the watchdog of a resumed pause still fired")
	default:
	}
}

func TestStoppingClearsAnOverlongPause(t *testing.T) {
	a, _ := pausedFor(t, 10*time.Minute, 20*time.Minute)
	a.Stop()
	if a.PausedTooLong() {
		t.Fatal("a stopped timer is not paused, so it cannot be paused too long")
	}
	if !a.Snapshot().PausedAt.IsZero() {
		t.Fatal("a stopped timer still records when it was paused")
	}
}

// A pause is only too long against a threshold, and a Timer built without one
// has nothing to measure against.
func TestAZeroThresholdNeverReportsTooLong(t *testing.T) {
	a, _ := pausedFor(t, 0, 24*time.Hour)
	if a.PausedTooLong() {
		t.Fatal("a timer with no threshold reported a pause as too long")
	}
}

// The pause's age is wall-clock time the daemon was not necessarily running
// for. A pause forgotten before a restart is still forgotten after it.
func TestARestoredPauseKeepsItsAge(t *testing.T) {
	a := New(25, 5, 15, 4)
	clk := newFakeClock(time.Date(2026, 9, 3, 10, 0, 0, 0, time.UTC))
	a.setClock(clk)
	a.SetPausedTooLongAfter(10 * time.Minute)
	changes := make(chan struct{}, 4)

	if err := a.Restore(pausedSnapshot(clk.Now().Add(-9*time.Minute)), clk.Now()); err != nil {
		t.Fatal(err)
	}
	if a.PausedTooLong() {
		t.Fatal("a nine-minute-old pause is not too long against a ten-minute threshold")
	}
	a.SetOnChange(func() { changes <- struct{}{} })

	clk.Advance(time.Minute)

	if !a.PausedTooLong() {
		t.Fatal("the restored pause did not become too long at its own tenth minute")
	}
	select {
	case <-changes:
	default:
		t.Fatal("the restored pause published nothing when it became too long")
	}
}

func TestARestoredPauseAlreadyPastTheThresholdIsTooLongAtOnce(t *testing.T) {
	a := New(25, 5, 15, 4)
	clk := newFakeClock(time.Date(2026, 9, 3, 10, 0, 0, 0, time.UTC))
	a.setClock(clk)
	a.SetPausedTooLongAfter(10 * time.Minute)

	if err := a.Restore(pausedSnapshot(clk.Now().Add(-3*time.Hour)), clk.Now()); err != nil {
		t.Fatal(err)
	}

	if !a.PausedTooLong() {
		t.Fatal("a three-hour-old pause came back as one that is not too long")
	}
}

// A pause with no recorded start cannot be aged, and the user is owed the
// whole threshold rather than an instant verdict.
func TestARestoredPauseWithNoRecordedStartAgesFromTheRestore(t *testing.T) {
	a := New(25, 5, 15, 4)
	clk := newFakeClock(time.Date(2026, 9, 3, 10, 0, 0, 0, time.UTC))
	a.setClock(clk)
	a.SetPausedTooLongAfter(10 * time.Minute)

	if err := a.Restore(pausedSnapshot(time.Time{}), clk.Now()); err != nil {
		t.Fatal(err)
	}

	clk.Advance(9 * time.Minute)
	if a.PausedTooLong() {
		t.Fatal("a pause of unknown age was aged from before the restore")
	}
	clk.Advance(time.Minute)
	if !a.PausedTooLong() {
		t.Fatal("a pause of unknown age never became too long")
	}
}

// A shortened threshold applies to the pause already in flight, the way an
// edited phase duration applies to the phase already running.
func TestAShortenedThresholdAppliesToThePauseInFlight(t *testing.T) {
	a, _ := pausedFor(t, 10*time.Minute, 5*time.Minute)

	a.SetPausedTooLongAfter(4 * time.Minute)

	if !a.PausedTooLong() {
		t.Fatal("the pause was not measured against the new threshold")
	}
}

func TestALengthenedThresholdRearmsThePauseInFlight(t *testing.T) {
	a, clk := pausedFor(t, 10*time.Minute, 5*time.Minute)
	changes := make(chan struct{}, 4)

	a.SetPausedTooLongAfter(30 * time.Minute)
	a.SetOnChange(func() { changes <- struct{}{} })

	clk.Advance(10 * time.Minute)
	if a.PausedTooLong() {
		t.Fatal("the pause was still measured against the old threshold")
	}
	select {
	case <-changes:
		t.Fatal("the old threshold's watchdog fired after the threshold moved")
	default:
	}

	clk.Advance(20 * time.Minute)
	if !a.PausedTooLong() {
		t.Fatal("the pause never became too long against the new threshold")
	}
}

// pausedSnapshot is a session saved mid-pause, five minutes into a pomodoro,
// paused at pausedAt.
func pausedSnapshot(pausedAt time.Time) Snapshot {
	return Snapshot{
		Engine: engine.Snapshot{
			State:          engine.Paused,
			LastPhase:      engine.Work,
			PausedFrom:     engine.Work,
			WorkDayStarted: true,
		},
		PausedRemaining: 20 * time.Minute,
		PausedElapsed:   5 * time.Minute,
		PausedAt:        pausedAt,
	}
}
