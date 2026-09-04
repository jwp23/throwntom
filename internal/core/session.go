package core

import (
	"fmt"
	"os"

	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/session"
	"github.com/jwp23/throwntom/v3/internal/task"
)

func (c *Core) saveSessionLocked() {
	if c.sessionPath == "" {
		return
	}
	data := session.Data{
		SavedAt:        c.now(),
		Timer:          c.timer.Snapshot(),
		FocusedTaskIDs: c.focusedIDs(),
	}
	if err := session.Save(c.sessionPath, data); err != nil {
		fmt.Fprintf(os.Stderr, "warning: session save failed: %v\n", err)
	}
}

// loadSession takes the Core lock: restoring the timer snapshot publishes a
// change, and the publish must not observe the half-restored focus list.
func (c *Core) loadSession() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.sessionPath == "" {
		return nil
	}
	data, err := session.Load(c.sessionPath)
	if err != nil {
		return err
	}
	if data.SavedAt.IsZero() {
		return nil
	}
	if !engine.IsSameDay(data.SavedAt, c.now()) {
		return nil
	}
	if reason := data.Timer.Engine.Invalid(); reason != "" {
		_, _ = fmt.Fprintf(c.warnOut, "warning: discarding inconsistent session: %s\n", reason)
		return nil
	}
	if err := c.timer.Restore(data.Timer, c.now()); err != nil {
		return err
	}
	if c.tasks != nil && len(data.FocusedTaskIDs) > 0 {
		activeByID := make(map[int]task.Task)
		for _, t := range c.tasks.Active() {
			activeByID[t.ID] = t
		}
		for _, id := range data.FocusedTaskIDs {
			if t, ok := activeByID[id]; ok {
				c.focused = append(c.focused, t)
			}
		}
	}
	c.timer.AdvanceDay(c.now())
	if dayUnderway(c.timer.Snapshot().Engine) {
		c.reminder.markTriggeredToday(c.now())
	}
	return nil
}

// dayUnderway reports whether the restored day is past the point the morning
// reminder exists to nudge it past: a phase is running, the day's work has
// begun, or the user declared the day over. Two of the three leave the engine
// idle, so state alone misses them.
//
// Callers read it from the advanced engine rather than from the session file:
// a rollover reopens the day, and the saved values would suppress the new
// day's reminder.
func dayUnderway(s engine.Snapshot) bool {
	return s.State != engine.Idle || s.WorkDayStarted || s.DayEnded
}
