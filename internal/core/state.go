package core

import (
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

type NextStage struct {
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
	NextStage           *NextStage   `json:"next_stage"`
	MorningPending      bool         `json:"morning_pending"`
	SnoozeUntil         *time.Time   `json:"snooze_until"`
	StatusLine          string       `json:"status_line"`
	FocusedTaskIDs      []int        `json:"focused_task_ids"`
	// ReminderRings counts the chimes the outstanding reminder has asked for,
	// resetting when it is retired. The daemon plays no sound of its own
	// (ADR-007), so a client sounds the repeat by watching this climb.
	ReminderRings int `json:"reminder_rings"`
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
		State:               state,
		PausedRemaining:     int(snap.PausedRemaining / time.Second),
		PausedFrom:          snap.Engine.PausedFrom,
		CompletedToday:      snap.Engine.CompletedToday,
		WorkSessionsInBlock: snap.Engine.WorkSessions,
		LongBreakEvery:      c.longBreakEvery,
		MorningPending:      morningPending,
		StatusLine:          statusLine,
		FocusedTaskIDs:      c.focusedIDs(),
		ReminderRings:       c.reminder.ringCount(),
	}
	if !snap.PhaseEndAt.IsZero() {
		end := snap.PhaseEndAt
		s.PhaseEndAt = &end
	}
	if next, dur, ok := c.nextStageLocked(); ok {
		s.NextStage = &NextStage{State: next, DurationSeconds: int(dur / time.Second)}
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
