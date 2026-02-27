package scheduler

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

type Scheduler struct {
	allowedWeekdays map[time.Weekday]struct{}
	hour            int
	minute          int
}

func New(days []string, hhmm string) *Scheduler {
	hour, minute, err := parseHHMM(hhmm)
	if err != nil {
		panic(err)
	}
	allowedWeekdays, err := parseWeekdays(days)
	if err != nil {
		panic(err)
	}
	return &Scheduler{
		allowedWeekdays: allowedWeekdays,
		hour:            hour,
		minute:          minute,
	}
}

func (s *Scheduler) ShouldTrigger(now time.Time) bool {
	if _, ok := s.allowedWeekdays[now.Weekday()]; !ok {
		return false
	}
	return now.Hour() == s.hour && now.Minute() == s.minute
}

func (s *Scheduler) NextTrigger(from time.Time) time.Time {
	candidate := time.Date(from.Year(), from.Month(), from.Day(), s.hour, s.minute, 0, 0, from.Location())
	if !candidate.After(from) {
		candidate = candidate.AddDate(0, 0, 1)
	}
	for {
		if _, ok := s.allowedWeekdays[candidate.Weekday()]; ok {
			return candidate
		}
		candidate = candidate.AddDate(0, 0, 1)
	}
}

func parseWeekdays(days []string) (map[time.Weekday]struct{}, error) {
	result := make(map[time.Weekday]struct{}, len(days))
	for _, day := range days {
		if wd, ok := toWeekday(day); ok {
			result[wd] = struct{}{}
			continue
		}
		return nil, fmt.Errorf("invalid weekday %q: expected Sun,Mon,Tue,Wed,Thu,Fri,Sat", day)
	}
	return result, nil
}

func toWeekday(day string) (time.Weekday, bool) {
	switch strings.ToLower(day) {
	case "sun":
		return time.Sunday, true
	case "mon":
		return time.Monday, true
	case "tue":
		return time.Tuesday, true
	case "wed":
		return time.Wednesday, true
	case "thu":
		return time.Thursday, true
	case "fri":
		return time.Friday, true
	case "sat":
		return time.Saturday, true
	default:
		return time.Sunday, false
	}
}

func parseHHMM(hhmm string) (int, int, error) {
	parts := strings.Split(hhmm, ":")
	if len(parts) != 2 {
		return 0, 0, fmt.Errorf("invalid time %q", hhmm)
	}
	hour, err := strconv.Atoi(parts[0])
	if err != nil || hour < 0 || hour > 23 {
		return 0, 0, fmt.Errorf("invalid hour in %q", hhmm)
	}
	minute, err := strconv.Atoi(parts[1])
	if err != nil || minute < 0 || minute > 59 {
		return 0, 0, fmt.Errorf("invalid minute in %q", hhmm)
	}
	return hour, minute, nil
}
