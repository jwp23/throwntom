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
		App:            c.cycle.Snapshot(),
		FocusedTaskIDs: c.focusedIDs(),
	}
	if err := session.Save(c.sessionPath, data); err != nil {
		fmt.Fprintf(os.Stderr, "warning: session save failed: %v\n", err)
	}
}

// loadSession takes the Core lock: restoring the app snapshot publishes a
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
	if err := c.cycle.Restore(data.App, c.now()); err != nil {
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
	c.cycle.AdvanceDay(c.now())
	if data.App.Engine.State != engine.Idle {
		c.state.markSkippedToday(c.now())
	}
	return nil
}
