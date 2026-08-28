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
	CompletedToday      int          `json:"completed_today"`
	WorkSessionsInBlock int          `json:"work_sessions_in_block"`
	LongBreakEvery      int          `json:"long_break_every"`
	NextStage           *NextStage   `json:"next_stage"`
	MorningPending      bool         `json:"morning_pending"`
	SnoozeUntil         *time.Time   `json:"snooze_until"`
	StatusLine          string       `json:"status_line"`
	FocusedTaskIDs      []int        `json:"focused_task_ids"`
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
		CompletedToday:      snap.Engine.CompletedToday,
		WorkSessionsInBlock: snap.Engine.WorkSessions,
		LongBreakEvery:      c.longBreakEvery,
		MorningPending:      morningPending,
		StatusLine:          statusLine,
		FocusedTaskIDs:      c.focusedIDs(),
	}
	if !snap.PhaseEndAt.IsZero() {
		end := snap.PhaseEndAt
		s.PhaseEndAt = &end
	}
	if next, dur, ok := c.nextStageLocked(); ok {
		s.NextStage = &NextStage{State: next, DurationSeconds: int(dur / time.Second)}
	}
	if until, ok := c.state.snoozeDeadline(); ok {
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
