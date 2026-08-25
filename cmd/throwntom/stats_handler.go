package main

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"
	"github.com/jwp23/throwntom/v3/internal/analytics"
)

func renderDashboard(dash analytics.Dashboard, now time.Time, tierLow, tierMid int) string {
	var sections []string

	// Today
	sections = append(sections, fmt.Sprintf("-- Today --\nPomodoros: %s    Focus: %s    Pauses: %d    Snoozes: %d",
		tierStyled(dash.Today.Pomodoros, tierLow, tierMid),
		formatDuration(dash.Today.FocusMinutes),
		dash.Today.Pauses, dash.Today.Snoozes))

	// This Week
	weekLine := fmt.Sprintf("-- This Week --\nPomodoros: %s    Focus: %s",
		tierStyled(dash.ThisWeek.Pomodoros, tierLow, tierMid),
		formatDuration(dash.ThisWeek.FocusMinutes))
	if len(dash.ThisWeek.DailyCounts) > 0 {
		var dayParts []string
		for _, dc := range dash.ThisWeek.DailyCounts {
			dayParts = append(dayParts, fmt.Sprintf("%s %s",
				dc.Date.Format("Mon"),
				tierStyled(dc.Count, tierLow, tierMid)))
		}
		weekLine += "\n" + strings.Join(dayParts, "  ")
	}
	sections = append(sections, weekLine)

	// This Month
	monthLine := fmt.Sprintf("-- This Month --\nPomodoros: %s    Focus: %s",
		tierStyled(dash.ThisMonth.Pomodoros, tierLow, tierMid),
		formatDuration(dash.ThisMonth.FocusMinutes))
	if dash.ThisMonth.Pomodoros > 0 {
		dayCount := now.Day()
		if dayCount > 0 {
			avg := float64(dash.ThisMonth.Pomodoros) / float64(dayCount)
			monthLine += fmt.Sprintf("    Avg: %.1f/day", avg)
		}
	}
	sections = append(sections, monthLine)

	// All Time
	allTimeLine := fmt.Sprintf("-- All Time --\nPomodoros: %s    Focus: %s",
		tierStyled(dash.AllTime.Pomodoros, tierLow, tierMid),
		formatDuration(dash.AllTime.FocusMinutes))
	sections = append(sections, allTimeLine)

	// Streaks
	sections = append(sections, fmt.Sprintf("-- Streaks --\nCurrent: %d days    Longest: %d days",
		dash.Streaks.Current, dash.Streaks.Longest))

	// Patterns
	if dash.AllTime.Pomodoros > 0 {
		sections = append(sections, fmt.Sprintf("-- Patterns --\nBest day: %s    Best hour: %d:00-%d:00\nSnooze rate: %.1f/pom    Pause rate: %.1f/pom",
			dash.Patterns.BestDay,
			dash.Patterns.BestHour, dash.Patterns.BestHour+1,
			dash.Patterns.SnoozeRate, dash.Patterns.PauseRate))
	}

	return strings.Join(sections, "\n\n")
}

func tierStyled(count, tierLow, tierMid int) string {
	s := tierStyle(count, tierLow, tierMid)
	return s.Render(fmt.Sprintf("%d", count))
}

func tierStyle(count, tierLow, tierMid int) lipgloss.Style {
	switch {
	case count > tierMid:
		return lipgloss.NewStyle().Foreground(colorGreen)
	case count > tierLow:
		return lipgloss.NewStyle().Foreground(colorAmber)
	default:
		return lipgloss.NewStyle().Foreground(colorDim)
	}
}

func formatDuration(minutes int) string {
	if minutes < 60 {
		return fmt.Sprintf("%dm", minutes)
	}
	h := minutes / 60
	m := minutes % 60
	if m == 0 {
		return fmt.Sprintf("%dh", h)
	}
	return fmt.Sprintf("%dh %dm", h, m)
}
