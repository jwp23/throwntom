package analytics

import (
	"time"

	"github.com/jwp23/throwntom/v3/internal/eventlog"
)

// dayLayout is the time.Format layout used as the map key for a calendar day.
const dayLayout = "2006-01-02"

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

type periodBounds struct {
	todayStart time.Time
	weekStart  time.Time
	monthStart time.Time
	endOfToday time.Time
}

type accumulator struct {
	dash       Dashboard
	pomDays    map[string]int
	hourCounts [24]int
	wdCounts   map[time.Weekday]int
	wdDays     map[time.Weekday]map[string]bool
	lastStart  time.Time
	hasStart   bool
}

func Compute(events []eventlog.Event, now time.Time) Dashboard {
	bounds := periodBounds{
		todayStart: startOfDay(now),
		weekStart:  startOfWeek(now),
		monthStart: startOfMonth(now),
		endOfToday: startOfDay(now).AddDate(0, 0, 1),
	}
	acc := accumulator{
		pomDays:  make(map[string]int),
		wdCounts: make(map[time.Weekday]int),
		wdDays:   make(map[time.Weekday]map[string]bool),
	}

	for _, ev := range events {
		acc.processEvent(ev, bounds)
	}

	acc.dash.ThisWeek.DailyCounts = buildDailyCounts(acc.pomDays, bounds.weekStart, now)
	acc.dash.ThisMonth.DailyCounts = buildDailyCounts(acc.pomDays, bounds.monthStart, now)
	acc.dash.Streaks = computeStreaks(acc.pomDays, now)
	acc.dash.Patterns = computePatterns(acc.hourCounts, acc.wdCounts, acc.wdDays, acc.dash.AllTime)

	return acc.dash
}

func (a *accumulator) processEvent(ev eventlog.Event, b periodBounds) {
	day := startOfDay(ev.Timestamp)
	dayKey := day.Format(dayLayout)
	periods := []*PeriodStats{&a.dash.Today, &a.dash.ThisWeek, &a.dash.ThisMonth}
	active := [3]bool{
		!day.Before(b.todayStart) && day.Before(b.endOfToday),
		!ev.Timestamp.Before(b.weekStart) && ev.Timestamp.Before(b.endOfToday),
		!ev.Timestamp.Before(b.monthStart) && ev.Timestamp.Before(b.endOfToday),
	}

	switch ev.Type {
	case "pomodoro_started":
		a.lastStart = ev.Timestamp
		a.hasStart = true
	case "pomodoro_completed":
		a.processCompletion(ev, dayKey, periods, active)
	case "stopped":
		// A stopped pomodoro was never finished, so the time it was open is
		// not focus time and must not be charged to a later completion.
		a.hasStart = false
	case "paused":
		a.dash.AllTime.Pauses++
		addToActive(periods, active, func(p *PeriodStats) { p.Pauses++ })
	case "snoozed":
		a.dash.AllTime.Snoozes++
		addToActive(periods, active, func(p *PeriodStats) { p.Snoozes++ })
	}
}

func (a *accumulator) processCompletion(ev eventlog.Event, dayKey string, periods []*PeriodStats, active [3]bool) {
	a.dash.AllTime.Pomodoros++
	a.pomDays[dayKey]++
	a.hourCounts[ev.Timestamp.Hour()]++
	wd := ev.Timestamp.Weekday()
	a.wdCounts[wd]++
	if a.wdDays[wd] == nil {
		a.wdDays[wd] = make(map[string]bool)
	}
	a.wdDays[wd][dayKey] = true
	addToActive(periods, active, func(p *PeriodStats) { p.Pomodoros++ })

	if a.hasStart {
		minutes := int(ev.Timestamp.Sub(a.lastStart).Minutes())
		a.dash.AllTime.FocusMinutes += minutes
		addToActive(periods, active, func(p *PeriodStats) { p.FocusMinutes += minutes })
		a.hasStart = false
	}
}

func addToActive(periods []*PeriodStats, active [3]bool, fn func(*PeriodStats)) {
	for i, p := range periods {
		if active[i] {
			fn(p)
		}
	}
}

func computePatterns(hourCounts [24]int, weekdayCounts map[time.Weekday]int, weekdayDays map[time.Weekday]map[string]bool, allTime PeriodStats) PatternStats {
	var p PatternStats

	bestHourCount := 0
	for h, c := range hourCounts {
		if c > bestHourCount {
			bestHourCount = c
			p.BestHour = h
		}
	}

	bestDayAvg := 0.0
	for wd := time.Sunday; wd <= time.Saturday; wd++ {
		days := len(weekdayDays[wd])
		if days > 0 {
			avg := float64(weekdayCounts[wd]) / float64(days)
			p.AvgByWeekday[wd] = avg
			if avg > bestDayAvg {
				bestDayAvg = avg
				p.BestDay = wd
			}
		}
	}

	if allTime.Pomodoros > 0 {
		p.SnoozeRate = float64(allTime.Snoozes) / float64(allTime.Pomodoros)
		p.PauseRate = float64(allTime.Pauses) / float64(allTime.Pomodoros)
	}

	return p
}

func buildDailyCounts(pomDays map[string]int, from, to time.Time) []DayCount {
	var counts []DayCount
	for d := from; !d.After(to); d = d.AddDate(0, 0, 1) {
		key := d.Format(dayLayout)
		if c, ok := pomDays[key]; ok {
			counts = append(counts, DayCount{Date: d, Count: c})
		}
	}
	return counts
}

func computeStreaks(pomDays map[string]int, now time.Time) StreakStats {
	if len(pomDays) == 0 {
		return StreakStats{}
	}

	daySet := make(map[string]bool, len(pomDays))
	for k := range pomDays {
		daySet[k] = true
	}

	today := startOfDay(now)
	current := 0
	for d := today; ; d = d.AddDate(0, 0, -1) {
		if daySet[d.Format(dayLayout)] {
			current++
		} else {
			break
		}
	}

	var sorted []time.Time
	for k := range pomDays {
		t, _ := time.ParseInLocation(dayLayout, k, now.Location())
		sorted = append(sorted, t)
	}
	sortDates(sorted)

	longest := 1
	streak := 1
	for i := 1; i < len(sorted); i++ {
		if sorted[i].Sub(sorted[i-1]) == 24*time.Hour {
			streak++
			if streak > longest {
				longest = streak
			}
		} else {
			streak = 1
		}
	}

	return StreakStats{Current: current, Longest: longest}
}

func sortDates(dates []time.Time) {
	for i := 1; i < len(dates); i++ {
		for j := i; j > 0 && dates[j].Before(dates[j-1]); j-- {
			dates[j], dates[j-1] = dates[j-1], dates[j]
		}
	}
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
