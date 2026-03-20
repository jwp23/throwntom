package scheduler

import (
	"fmt"
	"strconv"
	"strings"
	"time"
)

type dayTime struct {
	hour   int
	minute int
}

type Scheduler struct {
	times map[time.Weekday]dayTime
}

func New(dayTimes map[string]string) *Scheduler {
	times := make(map[time.Weekday]dayTime, len(dayTimes))
	for day, hhmm := range dayTimes {
		wd, ok := toWeekday(day)
		if !ok {
			panic(fmt.Sprintf("invalid weekday %q", day))
		}
		hour, minute, err := parseHHMM(hhmm)
		if err != nil {
			panic(err)
		}
		times[wd] = dayTime{hour: hour, minute: minute}
	}
	return &Scheduler{times: times}
}

func (s *Scheduler) ShouldTrigger(now time.Time) bool {
	dt, ok := s.times[now.Weekday()]
	if !ok {
		return false
	}
	return now.Hour() == dt.hour && now.Minute() == dt.minute
}

func (s *Scheduler) IsActiveNow(now time.Time) bool {
	dt, ok := s.times[now.Weekday()]
	if !ok {
		return false
	}
	return now.Hour() > dt.hour || (now.Hour() == dt.hour && now.Minute() >= dt.minute)
}

func (s *Scheduler) NextTrigger(from time.Time) time.Time {
	candidate := from.AddDate(0, 0, 0)
	for i := 0; i < 8; i++ {
		dt, ok := s.times[candidate.Weekday()]
		if ok {
			t := time.Date(candidate.Year(), candidate.Month(), candidate.Day(),
				dt.hour, dt.minute, 0, 0, from.Location())
			if t.After(from) {
				return t
			}
		}
		candidate = candidate.AddDate(0, 0, 1)
	}
	panic("no valid schedule day found within 8 days")
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
