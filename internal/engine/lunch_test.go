package engine

import "testing"

// workAndRest runs one pomodoro and the break it earns, both to completion,
// leaving the engine back in the next work period.
func workAndRest(e *Engine) {
	e.MarkPeriodComplete()
	e.ConfirmNext()
	e.MarkPeriodComplete()
	e.ConfirmNext()
}

func TestStartLunchEntersLunch(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.StartLunch()
	if e.State() != Lunch {
		t.Fatalf("state is %v, want Lunch", e.State())
	}
}

func TestLunchRunsToAwaitingConfirmThenWork(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartLunch()
	e.MarkPeriodComplete()
	if e.State() != AwaitingConfirm {
		t.Fatalf("state is %v, want AwaitingConfirm", e.State())
	}
	if next := e.NextPhase(); next != Work {
		t.Fatalf("next phase is %v, want Work", next)
	}
	e.ConfirmNext()
	if e.State() != Work {
		t.Fatalf("state is %v, want Work", e.State())
	}
}

// Lunch is the boundary between blocks: the pomodoros before it are done with,
// so the counter that earns the long break starts again while the day's total
// stands.
func TestLunchEndsTheBlockAndKeepsTheDayTotal(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	workAndRest(e)
	workAndRest(e)

	e.StartLunch()

	if got := e.WorkSessionsInBlock(); got != 0 {
		t.Fatalf("work sessions in block is %d, want 0", got)
	}
	if got := e.CompletedToday(); got != 2 {
		t.Fatalf("completed today is %d, want 2", got)
	}
}

// The pomodoros worked before lunch cannot shorten the way to the long break
// after it: a full block has to be worked on the far side.
func TestLongBreakComesAFullBlockAfterLunch(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	workAndRest(e)
	workAndRest(e)
	e.StartLunch()
	e.MarkPeriodComplete()
	e.ConfirmNext()

	for i := 1; i <= 3; i++ {
		e.MarkPeriodComplete()
		if next := e.NextPhase(); next != ShortBreak {
			t.Fatalf("break after post-lunch pomodoro %d is %v, want ShortBreak", i, next)
		}
		e.ConfirmNext()
		e.MarkPeriodComplete()
		e.ConfirmNext()
	}
	e.MarkPeriodComplete()
	if next := e.NextPhase(); next != LongBreak {
		t.Fatalf("break after the fourth post-lunch pomodoro is %v, want LongBreak", next)
	}
}

// Lunch displaces whatever was waiting, and the pomodoro the engine had
// already credited stays credited.
func TestLunchFromAwaitingConfirmKeepsTheCompletion(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()

	e.StartLunch()

	if e.State() != Lunch {
		t.Fatalf("state is %v, want Lunch", e.State())
	}
	if got := e.CompletedToday(); got != 1 {
		t.Fatalf("completed today is %d, want 1", got)
	}
}

// A day that has not started yet is opened by going to lunch, the way starting
// work opens it: there is a phase running, so the engine is no longer idle.
func TestLunchOpensTheWorkDay(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.SkipToday()

	e.StartLunch()

	snap := e.Snapshot()
	if !snap.WorkDayStarted {
		t.Fatal("work day is not started")
	}
	if snap.DayEnded {
		t.Fatal("day is still marked ended")
	}
	if reason := snap.Invalid(); reason != "" {
		t.Fatalf("snapshot is invalid: %s", reason)
	}
}

func TestLunchCanBePausedAndResumed(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartLunch()

	if !e.Pause() {
		t.Fatal("pause refused during lunch")
	}
	snap := e.Snapshot()
	if snap.PausedFrom != Lunch {
		t.Fatalf("paused from %v, want Lunch", snap.PausedFrom)
	}
	if reason := snap.Invalid(); reason != "" {
		t.Fatalf("paused snapshot is invalid: %s", reason)
	}
	if !e.Resume() {
		t.Fatal("resume refused")
	}
	if e.State() != Lunch {
		t.Fatalf("state is %v, want Lunch", e.State())
	}
}

// Coming back from lunch early is a skip like any other: the phase ends at the
// next stage's confirmation, and nothing is credited for it.
func TestSkippingLunchReachesAwaitingConfirm(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartLunch()

	if !e.SkipPhase() {
		t.Fatal("skip refused during lunch")
	}
	snap := e.Snapshot()
	if snap.State != AwaitingConfirm || snap.LastPhase != Lunch {
		t.Fatalf("snapshot is %v/%v, want awaiting_confirm/lunch", snap.State, snap.LastPhase)
	}
	if reason := snap.Invalid(); reason != "" {
		t.Fatalf("snapshot is invalid: %s", reason)
	}
	if got := e.CompletedToday(); got != 0 {
		t.Fatalf("completed today is %d, want 0", got)
	}
}

// A stop during lunch owes nothing, but a stop at the confirmation lunch
// reaches owes the pomodoro that follows it.
func TestStartAfterLunchIsOwedWork(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartLunch()
	e.MarkPeriodComplete()
	e.Stop()

	if owed := e.OwedPhase(); owed != Work {
		t.Fatalf("owed phase is %v, want Work", owed)
	}
}

func TestLunchStateRoundTripsThroughItsName(t *testing.T) {
	if got := Lunch.String(); got != "lunch" {
		t.Fatalf("Lunch is named %q, want %q", got, "lunch")
	}
	parsed, ok := StateFromString("lunch")
	if !ok || parsed != Lunch {
		t.Fatalf("StateFromString(%q) = %v, %v; want Lunch, true", "lunch", parsed, ok)
	}
}
