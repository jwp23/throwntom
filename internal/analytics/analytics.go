package analytics

import (
	"time"

	"github.com/jwp23/throwntom/v3/internal/eventlog"
)

type Dashboard struct {
	Today     PeriodStats
	ThisWeek  PeriodStats
	ThisMonth PeriodStats
	AllTime   PeriodStats
	Streaks   StreakStats
	Patterns  PatternStats
}

type PeriodStats struct {
	Pomodoros    int
	FocusMinutes int
	Pauses       int
	Snoozes      int
	DailyCounts  []DayCount
}

type DayCount struct {
	Date  time.Time
	Count int
}

type StreakStats struct {
	Current int
	Longest int
}

type PatternStats struct {
	BestDay      time.Weekday
	BestHour     int
	AvgByWeekday [7]float64
	SnoozeRate   float64
	PauseRate    float64
}

func Compute(events []eventlog.Event, now time.Time) Dashboard {
	var dash Dashboard

	todayStart := startOfDay(now)
	weekStart := startOfWeek(now)
	monthStart := startOfMonth(now)

	pomDays := make(map[string]int)
	var lastStart time.Time
	var hasStart bool

	for _, ev := range events {
		day := startOfDay(ev.Timestamp)
		dayKey := day.Format("2006-01-02")
		inToday := !day.Before(todayStart) && day.Before(todayStart.AddDate(0, 0, 1))
		inWeek := !ev.Timestamp.Before(weekStart) && ev.Timestamp.Before(now.AddDate(0, 0, 1))
		inMonth := !ev.Timestamp.Before(monthStart) && ev.Timestamp.Before(now.AddDate(0, 0, 1))

		switch ev.Type {
		case "pomodoro_started":
			lastStart = ev.Timestamp
			hasStart = true

		case "pomodoro_completed":
			dash.AllTime.Pomodoros++
			pomDays[dayKey]++
			if inToday {
				dash.Today.Pomodoros++
			}
			if inWeek {
				dash.ThisWeek.Pomodoros++
			}
			if inMonth {
				dash.ThisMonth.Pomodoros++
			}
			if hasStart {
				minutes := int(ev.Timestamp.Sub(lastStart).Minutes())
				dash.AllTime.FocusMinutes += minutes
				if inToday {
					dash.Today.FocusMinutes += minutes
				}
				if inWeek {
					dash.ThisWeek.FocusMinutes += minutes
				}
				if inMonth {
					dash.ThisMonth.FocusMinutes += minutes
				}
				hasStart = false
			}

		case "paused":
			dash.AllTime.Pauses++
			if inToday {
				dash.Today.Pauses++
			}
			if inWeek {
				dash.ThisWeek.Pauses++
			}
			if inMonth {
				dash.ThisMonth.Pauses++
			}

		case "snoozed":
			dash.AllTime.Snoozes++
			if inToday {
				dash.Today.Snoozes++
			}
			if inWeek {
				dash.ThisWeek.Snoozes++
			}
			if inMonth {
				dash.ThisMonth.Snoozes++
			}
		}
	}

	dash.ThisWeek.DailyCounts = buildDailyCounts(pomDays, weekStart, now)
	dash.ThisMonth.DailyCounts = buildDailyCounts(pomDays, monthStart, now)

	return dash
}

func buildDailyCounts(pomDays map[string]int, from, to time.Time) []DayCount {
	var counts []DayCount
	for d := from; !d.After(to); d = d.AddDate(0, 0, 1) {
		key := d.Format("2006-01-02")
		if c, ok := pomDays[key]; ok {
			counts = append(counts, DayCount{Date: d, Count: c})
		}
	}
	return counts
}

func startOfDay(t time.Time) time.Time {
	y, m, d := t.Date()
	return time.Date(y, m, d, 0, 0, 0, 0, t.Location())
}

func startOfWeek(t time.Time) time.Time {
	day := startOfDay(t)
	weekday := day.Weekday()
	if weekday == time.Sunday {
		weekday = 7
	}
	return day.AddDate(0, 0, -int(weekday-time.Monday))
}

func startOfMonth(t time.Time) time.Time {
	y, m, _ := t.Date()
	return time.Date(y, m, 1, 0, 0, 0, 0, t.Location())
}
