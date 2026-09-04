package core

import (
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// Stage is a phase the timer could move into, and how long it would run for.
type Stage struct {
	State           engine.State `json:"state"`
	DurationSeconds int          `json:"duration"`
}

type State struct {
	State               engine.State `json:"state"`
	PhaseEndAt          *time.Time   `json:"phase_end_at"`
	PausedRemaining     int          `json:"paused_remaining"`
	PausedFrom          engine.State `json:"paused_from"`
	CompletedToday      int          `json:"completed_today"`
	WorkSessionsInBlock int          `json:"work_sessions_in_block"`
	LongBreakEvery      int          `json:"long_break_every"`
	// NextStage is what confirm would move on to, so it is present only while
	// a finished phase is waiting to be confirmed.
	NextStage *Stage `json:"next_stage"`
	// OwedStage is what start would enter, so it is present only while the
	// timer is idle and start is the verb on offer. Stop is a suspend, so an
	// idle timer can owe the break it earned; without this a client shows Idle
	// beside a Start control and cannot say which phase it will begin.
	OwedStage      *Stage `json:"owed_stage"`
	MorningPending bool   `json:"morning_pending"`
	// DayEnded is true once the user has ended the work day, so a client can
	// tell an idle timer that is ready to go from one that is done until
	// tomorrow. Nothing else in this document distinguishes them.
	DayEnded       bool       `json:"day_ended"`
	SnoozeUntil    *time.Time `json:"snooze_until"`
	StatusLine     string     `json:"status_line"`
	FocusedTaskIDs []int      `json:"focused_task_ids"`
	// ReminderRings counts the chimes the outstanding reminder has asked for,
	// resetting when it is retired. The daemon plays no sound of its own
	// (ADR-007), so a client sounds the repeat by watching this climb.
	ReminderRings int `json:"reminder_rings"`
	// FloatWindowWhenWaiting is the user's `float_window_when_waiting`
	// setting, passed through for whichever client has a window to raise. The
	// daemon neither reads nor enforces it; presentation is the client's
	// (ADR-003).
	FloatWindowWhenWaiting bool `json:"float_window_when_waiting"`
	// PausedTooLong is true once the pause in flight has outlasted
	// `paused_too_long_minutes`. The daemon keeps the clock and says only
	// that the pause has been forgotten; asking for the user's attention is
	// the client's (ADR-003).
	PausedTooLong bool `json:"paused_too_long"`
	// BounceDockWhenPaused is the user's `bounce_dock_when_paused` setting,
	// passed through for the macOS app the way FloatWindowWhenWaiting is. The
	// daemon neither reads nor enforces it: paused_too_long above turns true
	// on the same clock either way, and only the client's decision to bounce
	// the Dock (ADR-003) depends on this.
	BounceDockWhenPaused bool `json:"bounce_dock_when_paused"`
}

func (c *Core) State() State {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.stateLocked()
}

func (c *Core) stateLocked() State {
	statusLine, state, morningPending := c.statusLocked()
	snap := c.timer.Snapshot()
	s := State{
		State:                  state,
		PausedRemaining:        int(snap.PausedRemaining / time.Second),
		PausedFrom:             snap.Engine.PausedFrom,
		CompletedToday:         snap.Engine.CompletedToday,
		WorkSessionsInBlock:    snap.Engine.WorkSessions,
		LongBreakEvery:         c.longBreakEvery,
		MorningPending:         morningPending,
		DayEnded:               snap.Engine.DayEnded,
		StatusLine:             statusLine,
		FocusedTaskIDs:         c.focusedIDs(),
		ReminderRings:          c.reminder.ringCount(),
		FloatWindowWhenWaiting: c.floatWindowWhenWaiting,
		PausedTooLong:          c.timer.PausedTooLong(),
		BounceDockWhenPaused:   c.bounceDockWhenPaused,
	}
	if !snap.PhaseEndAt.IsZero() {
		end := snap.PhaseEndAt
		s.PhaseEndAt = &end
	}
	if next, dur, ok := c.nextStageLocked(); ok {
		s.NextStage = &Stage{State: next, DurationSeconds: int(dur / time.Second)}
	}
	if owed, dur, ok := c.owedStageLocked(); ok {
		s.OwedStage = &Stage{State: owed, DurationSeconds: int(dur / time.Second)}
	}
	if until, ok := c.reminder.snoozeDeadline(); ok {
		s.SnoozeUntil = &until
	}
	return s
}

func (c *Core) focusedIDs() []int {
	ids := make([]int, 0, len(c.focused))
	for _, t := range c.focused {
		ids = append(ids, t.ID)
	}
	return ids
}
