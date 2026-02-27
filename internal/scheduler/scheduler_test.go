package scheduler

import (
	"testing"
	"time"
)

func TestShouldTriggerMorningReminder(t *testing.T) {
	s := New([]string{"Mon", "Tue", "Wed", "Thu", "Fri"}, "09:15")
	at := time.Date(2026, 3, 2, 9, 15, 0, 0, time.Local)
	if !s.ShouldTrigger(at) {
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

func TestNewPanicsOnUnknownWeekday(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic for unknown weekday")
		}
	}()
	New([]string{"Monday"}, "09:15")
}
