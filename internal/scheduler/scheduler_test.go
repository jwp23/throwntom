package scheduler

import (
	"testing"
	"time"
)

func TestShouldTriggerMorningReminder(t *testing.T) {
	s := New([]string{"Mon", "Tue", "Wed", "Thu", "Fri"}, "09:15")
	if !s.ShouldTrigger(time.Date(2026, 3, 2, 9, 15, 0, 0, time.Local)) {
		t.Fatal("expected trigger at scheduled weekday/time")
	}
}

func TestNextTriggerSkipsWeekend(t *testing.T) {
	s := New([]string{"Mon", "Tue", "Wed", "Thu", "Fri"}, "09:15")
	from := time.Date(2026, 2, 28, 12, 0, 0, 0, time.Local) // Saturday
	next := s.NextTrigger(from)
	if next.Weekday() != time.Monday {
		t.Fatalf("expected Monday trigger, got %s", next.Weekday())
	}
}

func TestIsActiveNowBeforeScheduledTime(t *testing.T) {
	s := New([]string{"Mon"}, "09:15")
	// Monday at 09:14 — before scheduled time
	now := time.Date(2026, 3, 2, 9, 14, 0, 0, time.Local)
	if s.IsActiveNow(now) {
		t.Fatal("expected IsActiveNow=false before scheduled time")
	}
}

func TestIsActiveNowAtScheduledTime(t *testing.T) {
	s := New([]string{"Mon"}, "09:15")
	// Monday at 09:15 — exactly at scheduled time
	now := time.Date(2026, 3, 2, 9, 15, 0, 0, time.Local)
	if !s.IsActiveNow(now) {
		t.Fatal("expected IsActiveNow=true at scheduled time")
	}
}

func TestIsActiveNowAfterScheduledTime(t *testing.T) {
	s := New([]string{"Mon"}, "09:15")
	// Monday at 10:00 — after scheduled time
	now := time.Date(2026, 3, 2, 10, 0, 0, 0, time.Local)
	if !s.IsActiveNow(now) {
		t.Fatal("expected IsActiveNow=true after scheduled time")
	}
}

func TestIsActiveNowOnNonAllowedDay(t *testing.T) {
	s := New([]string{"Mon", "Tue", "Wed", "Thu", "Fri"}, "09:15")
	// Saturday at 10:00 — not an allowed day
	now := time.Date(2026, 2, 28, 10, 0, 0, 0, time.Local)
	if s.IsActiveNow(now) {
		t.Fatal("expected IsActiveNow=false on non-allowed day")
	}
}

func TestNewPanicsOnUnknownWeekday(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic for unknown weekday")
		}
	}()
	New([]string{"Monday"}, "09:15")
}
