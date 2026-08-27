package engine

import (
	"encoding/json"
	"testing"
	"time"
)

func TestConfirmTransitionWorkToShortBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	if e.State() != AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm")
	}
	e.ConfirmNext()
	if e.State() != ShortBreak {
		t.Fatalf("expected ShortBreak")
	}
}

func TestConfirmTransitionBreakToWork(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	if e.State() != Work {
		t.Fatalf("expected Work")
	}
}

func TestEveryFourthWorkGoesToLongBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for i := 0; i < 3; i++ {
		e.MarkPeriodComplete()
		e.ConfirmNext()
		e.MarkPeriodComplete()
		e.ConfirmNext()
	}
	e.MarkPeriodComplete()
	e.ConfirmNext()
	if e.State() != LongBreak {
		t.Fatalf("expected LongBreak, got %v", e.State())
	}
}

func TestNextPhaseFromWorkIsShortBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	if got := e.NextPhase(); got != ShortBreak {
		t.Fatalf("expected ShortBreak, got %v", got)
	}
}

func TestNextPhaseFromWorkEveryFourthIsLongBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for i := 0; i < 3; i++ {
		e.MarkPeriodComplete()
		e.ConfirmNext()
		e.MarkPeriodComplete()
		e.ConfirmNext()
	}
	e.MarkPeriodComplete()
	if got := e.NextPhase(); got != LongBreak {
		t.Fatalf("expected LongBreak, got %v", got)
	}
}

func TestNextPhaseFromShortBreakIsWork(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	e.MarkPeriodComplete()
	if got := e.NextPhase(); got != Work {
		t.Fatalf("expected Work, got %v", got)
	}
}

func TestNextPhaseOutsideAwaitingConfirmReturnsIdle(t *testing.T) {
	e := New(25, 5, 15, 4)
	if got := e.NextPhase(); got != Idle {
		t.Fatalf("expected Idle when not awaiting confirm, got %v", got)
	}
	e.StartWork()
	if got := e.NextPhase(); got != Idle {
		t.Fatalf("expected Idle during Work, got %v", got)
	}
}

func TestNextPhaseDoesNotMutateState(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	_ = e.NextPhase()
	if e.State() != AwaitingConfirm {
		t.Fatalf("NextPhase must not mutate state, got %v", e.State())
	}
	_ = e.NextPhase()
	if e.State() != AwaitingConfirm {
		t.Fatalf("NextPhase called twice must not mutate, got %v", e.State())
	}
}

func TestCompletedTodayResetsOnFirstStart(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	if e.CompletedToday() != 1 {
		t.Fatalf("expected completedToday=1")
	}
	e.SkipToday()
	e.StartWork()
	if e.CompletedToday() != 0 {
		t.Fatalf("expected reset on first start, got %d", e.CompletedToday())
	}
}

func TestStartNewCycleResetsBlockButPreservesCompletedToday(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	e.MarkPeriodComplete()

	if e.CompletedToday() != 2 {
		t.Fatalf("expected completedToday=2 before reset, got %d", e.CompletedToday())
	}
	if e.WorkSessionsInBlock() != 2 {
		t.Fatalf("expected block progress=2 before reset, got %d", e.WorkSessionsInBlock())
	}

	e.StartNewCycle()

	if e.State() != Work {
		t.Fatalf("expected Work after new cycle, got %v", e.State())
	}
	if e.WorkSessionsInBlock() != 0 {
		t.Fatalf("expected block progress reset, got %d", e.WorkSessionsInBlock())
	}
	if e.CompletedToday() != 2 {
		t.Fatalf("expected completedToday preserved, got %d", e.CompletedToday())
	}
}

func TestStateStringRoundTrip(t *testing.T) {
	states := []struct {
		state State
		name  string
	}{
		{Idle, "idle"},
		{Work, "work"},
		{ShortBreak, "short_break"},
		{LongBreak, "long_break"},
		{AwaitingConfirm, "awaiting_confirm"},
		{Paused, "paused"},
	}
	for _, tc := range states {
		if got := tc.state.String(); got != tc.name {
			t.Errorf("State(%d).String() = %q, want %q", tc.state, got, tc.name)
		}
		parsed, ok := StateFromString(tc.name)
		if !ok {
			t.Errorf("StateFromString(%q) returned ok=false", tc.name)
		}
		if parsed != tc.state {
			t.Errorf("StateFromString(%q) = %d, want %d", tc.name, parsed, tc.state)
		}
	}
}

func TestStateFromStringUnknown(t *testing.T) {
	got, ok := StateFromString("bogus")
	if ok {
		t.Fatal("expected ok=false for unknown state string")
	}
	if got != Idle {
		t.Fatalf("expected Idle for unknown state, got %d", got)
	}
}

func TestStateMarshalTextRoundTrip(t *testing.T) {
	for _, s := range []State{Idle, Work, ShortBreak, LongBreak, AwaitingConfirm, Paused} {
		data, err := s.MarshalText()
		if err != nil {
			t.Fatalf("MarshalText(%d): %v", s, err)
		}
		var parsed State
		if err := parsed.UnmarshalText(data); err != nil {
			t.Fatalf("UnmarshalText(%q): %v", data, err)
		}
		if parsed != s {
			t.Errorf("round-trip failed: %d -> %q -> %d", s, data, parsed)
		}
	}
}

func TestSnapshotRestoreRoundTrip(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	e.Pause()

	snap := e.Snapshot()

	e2 := New(25, 5, 15, 4)
	e2.Restore(snap)

	if e2.State() != Paused {
		t.Fatalf("expected Paused, got %v", e2.State())
	}
	if e2.CompletedToday() != 1 {
		t.Fatalf("expected completedToday=1, got %d", e2.CompletedToday())
	}
	if e2.WorkSessionsInBlock() != 1 {
		t.Fatalf("expected workSessionsBlock=1, got %d", e2.WorkSessionsInBlock())
	}
}

func TestSnapshotRestorePreservesAllFields(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()

	snap := e.Snapshot()
	if snap.State != AwaitingConfirm {
		t.Fatalf("snapshot state: expected AwaitingConfirm, got %v", snap.State)
	}
	if snap.LastPhase != Work {
		t.Fatalf("snapshot lastPhase: expected Work, got %v", snap.LastPhase)
	}
	if snap.CompletedToday != 1 {
		t.Fatalf("snapshot completedToday: expected 1, got %d", snap.CompletedToday)
	}
	if snap.WorkSessions != 1 {
		t.Fatalf("snapshot workSessions: expected 1, got %d", snap.WorkSessions)
	}
	if !snap.WorkDayStarted {
		t.Fatal("snapshot workDayStarted: expected true")
	}
}

func TestAdvanceDayResetsOnNewDay(t *testing.T) {
	e := New(25, 5, 15, 4)
	yesterday := time.Date(2026, 3, 5, 17, 0, 0, 0, time.Local)
	e.AdvanceDay(yesterday)
	e.StartWork()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	e.MarkPeriodComplete()

	if e.CompletedToday() != 2 {
		t.Fatalf("expected completedToday=2, got %d", e.CompletedToday())
	}

	today := time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)
	e.AdvanceDay(today)

	if e.CompletedToday() != 0 {
		t.Fatalf("expected completedToday=0 after day rollover, got %d", e.CompletedToday())
	}
	if e.WorkSessionsInBlock() != 0 {
		t.Fatalf("expected workSessionsBlock=0 after day rollover, got %d", e.WorkSessionsInBlock())
	}
}

func TestAdvanceDaySameDayIsNoop(t *testing.T) {
	e := New(25, 5, 15, 4)
	now := time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)
	e.AdvanceDay(now)
	e.StartWork()
	e.MarkPeriodComplete()

	later := time.Date(2026, 3, 6, 17, 0, 0, 0, time.Local)
	e.AdvanceDay(later)

	if e.CompletedToday() != 1 {
		t.Fatalf("expected completedToday=1 on same day, got %d", e.CompletedToday())
	}
}

func TestAdvanceDayZeroDateRecordsWithoutReset(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()

	if e.CompletedToday() != 1 {
		t.Fatalf("expected completedToday=1, got %d", e.CompletedToday())
	}

	now := time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)
	e.AdvanceDay(now)

	if e.CompletedToday() != 1 {
		t.Fatalf("expected completedToday=1 preserved on first AdvanceDay, got %d", e.CompletedToday())
	}

	tomorrow := time.Date(2026, 3, 7, 9, 0, 0, 0, time.Local)
	e.AdvanceDay(tomorrow)

	if e.CompletedToday() != 0 {
		t.Fatalf("expected completedToday=0 after day rollover, got %d", e.CompletedToday())
	}
}

func TestAdvanceDaySnapshotIncludesWorkDate(t *testing.T) {
	e := New(25, 5, 15, 4)
	now := time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)
	e.AdvanceDay(now)

	snap := e.Snapshot()
	if snap.WorkDate.IsZero() {
		t.Fatal("expected WorkDate to be set in snapshot")
	}

	e2 := New(25, 5, 15, 4)
	e2.Restore(snap)

	later := time.Date(2026, 3, 6, 17, 0, 0, 0, time.Local)
	e2.AdvanceDay(later)
	if e2.CompletedToday() != 0 {
		t.Fatalf("expected completedToday=0 after restore, got %d", e2.CompletedToday())
	}
}

func TestIsSameDay(t *testing.T) {
	loc := time.Local
	tests := []struct {
		name string
		a, b time.Time
		want bool
	}{
		{"same day", time.Date(2026, 3, 5, 10, 0, 0, 0, loc), time.Date(2026, 3, 5, 23, 59, 0, 0, loc), true},
		{"different day", time.Date(2026, 3, 5, 23, 59, 0, 0, loc), time.Date(2026, 3, 6, 0, 1, 0, 0, loc), false},
		{"different month", time.Date(2026, 2, 28, 12, 0, 0, 0, loc), time.Date(2026, 3, 1, 12, 0, 0, 0, loc), false},
		{"same midnight", time.Date(2026, 3, 5, 0, 0, 0, 0, loc), time.Date(2026, 3, 5, 0, 0, 0, 0, loc), true},
	}
	for _, tc := range tests {
		if got := IsSameDay(tc.a, tc.b); got != tc.want {
			t.Errorf("%s: IsSameDay(%v, %v) = %v, want %v", tc.name, tc.a, tc.b, got, tc.want)
		}
	}
}

func TestStateJSONRoundTrip(t *testing.T) {
	type wrapper struct {
		S State `json:"s"`
	}
	for _, s := range []State{Idle, Work, ShortBreak, LongBreak, AwaitingConfirm, Paused} {
		w := wrapper{S: s}
		data, err := json.Marshal(w)
		if err != nil {
			t.Fatalf("json.Marshal: %v", err)
		}
		var got wrapper
		if err := json.Unmarshal(data, &got); err != nil {
			t.Fatalf("json.Unmarshal: %v", err)
		}
		if got.S != s {
			t.Errorf("JSON round-trip failed: %d -> %s -> %d", s, data, got.S)
		}
	}
}
