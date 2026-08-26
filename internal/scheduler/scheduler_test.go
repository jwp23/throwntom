package scheduler

import (
	"testing"
	"time"
)

func TestShouldTriggerMorningReminder(t *testing.T) {
	s := New(map[string]string{
		"Mon": "09:15", "Tue": "09:15", "Wed": "09:15", "Thu": "09:15", "Fri": "09:15",
	})
	if !s.ShouldTrigger(time.Date(2026, 3, 2, 9, 15, 0, 0, time.Local)) {
		t.Fatal("expected trigger at scheduled weekday/time")
	}
}

func TestNextTriggerSkipsWeekend(t *testing.T) {
	s := New(map[string]string{
		"Mon": "09:15", "Tue": "09:15", "Wed": "09:15", "Thu": "09:15", "Fri": "09:15",
	})
	from := time.Date(2026, 2, 28, 12, 0, 0, 0, time.Local) // Saturday
	next := s.NextTrigger(from)
	if next.Weekday() != time.Monday {
		t.Fatalf("expected Monday trigger, got %s", next.Weekday())
	}
}

func TestIsActiveNowBeforeScheduledTime(t *testing.T) {
	s := New(map[string]string{"Mon": "09:15"})
	if s.IsActiveNow(time.Date(2026, 3, 2, 9, 14, 0, 0, time.Local)) {
		t.Fatal("expected IsActiveNow=false before scheduled time")
	}
}

func TestIsActiveNowAtScheduledTime(t *testing.T) {
	s := New(map[string]string{"Mon": "09:15"})
	if !s.IsActiveNow(time.Date(2026, 3, 2, 9, 15, 0, 0, time.Local)) {
		t.Fatal("expected IsActiveNow=true at scheduled time")
	}
}

func TestIsActiveNowAfterScheduledTime(t *testing.T) {
	s := New(map[string]string{"Mon": "09:15"})
	if !s.IsActiveNow(time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local)) {
		t.Fatal("expected IsActiveNow=true after scheduled time")
	}
}

func TestIsActiveNowOnNonAllowedDay(t *testing.T) {
	s := New(map[string]string{
		"Mon": "09:15", "Tue": "09:15", "Wed": "09:15", "Thu": "09:15", "Fri": "09:15",
	})
	if s.IsActiveNow(time.Date(2026, 2, 28, 10, 0, 0, 0, time.Local)) { // Saturday
		t.Fatal("expected IsActiveNow=false on non-allowed day")
	}
}

func TestNewPanicsOnUnknownWeekday(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic for unknown weekday")
		}
	}()
	New(map[string]string{"Monday": "09:15"})
}

// --- Per-day time tests ---

func TestShouldTriggerPerDayTime(t *testing.T) {
	s := New(map[string]string{
		"Mon": "09:00",
		"Fri": "10:00",
	})
	// Monday at 09:00 should trigger
	if !s.ShouldTrigger(time.Date(2026, 3, 2, 9, 0, 0, 0, time.Local)) {
		t.Fatal("expected trigger on Monday at 09:00")
	}
	// Monday at 10:00 should NOT trigger (that's Friday's time)
	if s.ShouldTrigger(time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local)) {
		t.Fatal("should not trigger on Monday at 10:00")
	}
	// Friday at 10:00 should trigger
	if !s.ShouldTrigger(time.Date(2026, 3, 6, 10, 0, 0, 0, time.Local)) {
		t.Fatal("expected trigger on Friday at 10:00")
	}
	// Friday at 09:00 should NOT trigger (that's Monday's time)
	if s.ShouldTrigger(time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)) {
		t.Fatal("should not trigger on Friday at 09:00")
	}
}

func TestIsActiveNowPerDayTime(t *testing.T) {
	s := New(map[string]string{
		"Mon": "09:00",
		"Fri": "10:00",
	})
	// Monday at 08:59 — before Monday's time
	if s.IsActiveNow(time.Date(2026, 3, 2, 8, 59, 0, 0, time.Local)) {
		t.Fatal("expected not active before Monday's time")
	}
	// Monday at 09:00 — at Monday's time
	if !s.IsActiveNow(time.Date(2026, 3, 2, 9, 0, 0, 0, time.Local)) {
		t.Fatal("expected active at Monday's time")
	}
	// Friday at 09:59 — before Friday's time
	if s.IsActiveNow(time.Date(2026, 3, 6, 9, 59, 0, 0, time.Local)) {
		t.Fatal("expected not active before Friday's time")
	}
	// Friday at 10:00 — at Friday's time
	if !s.IsActiveNow(time.Date(2026, 3, 6, 10, 0, 0, 0, time.Local)) {
		t.Fatal("expected active at Friday's time")
	}
}

func TestNextTriggerPerDayTime(t *testing.T) {
	s := New(map[string]string{
		"Mon": "09:00",
		"Fri": "10:00",
	})
	// From Monday 09:01 — next should be Friday 10:00
	from := time.Date(2026, 3, 2, 9, 1, 0, 0, time.Local)
	next := s.NextTrigger(from)
	if next.Weekday() != time.Friday {
		t.Fatalf("expected Friday, got %s", next.Weekday())
	}
	if next.Hour() != 10 || next.Minute() != 0 {
		t.Fatalf("expected 10:00, got %02d:%02d", next.Hour(), next.Minute())
	}

	// From Friday 10:01 — next should be Monday 09:00
	from = time.Date(2026, 3, 6, 10, 1, 0, 0, time.Local)
	next = s.NextTrigger(from)
	if next.Weekday() != time.Monday {
		t.Fatalf("expected Monday, got %s", next.Weekday())
	}
	if next.Hour() != 9 || next.Minute() != 0 {
		t.Fatalf("expected 09:00, got %02d:%02d", next.Hour(), next.Minute())
	}
}
