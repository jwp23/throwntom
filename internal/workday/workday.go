// Package workday says which work day a moment belongs to.
//
// A work day runs from a configurable start hour to the next, not from
// midnight to midnight (ADR-013), so an overnight shift is one day: the
// counters, the long-break cadence and the once-a-day reminder all hold
// across midnight and turn over together at the start hour instead. Every
// part of the program that has to ask which day it is asks here, so the
// answers cannot drift apart.
package workday

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// Start is the time of day a work day begins. Its zero value is midnight,
// which is the calendar day.
type Start struct {
	hour   int
	minute int
}

var (
	errFormat = errors.New("expected HH:MM")
	errHour   = errors.New("hour must be between 00 and 23")
	errMinute = errors.New("minute must be between 00 and 59")
)

// ParseStart reads a start hour written as 24-hour HH:MM, the way the config
// writes every other time of day.
func ParseStart(hhmm string) (Start, error) {
	hour, minute, found := strings.Cut(hhmm, ":")
	if !found || len(hour) != 2 || len(minute) != 2 {
		return Start{}, errFormat
	}
	h, err := strconv.Atoi(hour)
	if err != nil || h < 0 || h > 23 {
		return Start{}, errHour
	}
	m, err := strconv.Atoi(minute)
	if err != nil || m < 0 || m > 59 {
		return Start{}, errMinute
	}
	return Start{hour: h, minute: m}, nil
}

// MustParseStart is ParseStart for a value the config has already validated,
// so a caller with nowhere to put an error does not have to invent one. It
// panics on anything else, as scheduler.New does with the schedule times.
func MustParseStart(hhmm string) Start {
	s, err := ParseStart(hhmm)
	if err != nil {
		panic(fmt.Sprintf("workday: invalid start %q: %v", hhmm, err))
	}
	return s
}

// Same reports whether a and b fall in the same work day.
func (s Start) Same(a, b time.Time) bool {
	ay, am, ad := s.date(a)
	by, bm, bd := s.date(b)
	return ay == by && am == bm && ad == bd
}

// Key names the work day t falls in, as an ISO date. It is the same day Same
// compares, in a form that can be stored and compared as a string.
func (s Start) Key(t time.Time) string {
	y, m, d := s.date(t)
	return fmt.Sprintf("%04d-%02d-%02d", y, int(m), d)
}

// date is the calendar date of the work day containing t: t's own date once
// the day has started, and the day before until it does.
//
// The comparison is against the wall clock and nothing else, so a day that a
// DST transition makes 23 or 25 hours long is still one work day, and a start
// hour the clock skips over still begins the day it names. There is no
// handling for the zone itself changing; the boundary means the hour the
// clock reads, wherever it is read.
func (s Start) date(t time.Time) (int, time.Month, int) {
	if s.beforeStart(t) {
		t = t.AddDate(0, 0, -1)
	}
	return t.Date()
}

// beforeStart reports whether t's wall clock has yet to reach the start hour.
func (s Start) beforeStart(t time.Time) bool {
	hour, minute, _ := t.Clock()
	return hour < s.hour || (hour == s.hour && minute < s.minute)
}
