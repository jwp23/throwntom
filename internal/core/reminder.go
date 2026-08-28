package core

import (
	"context"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// runMorningSchedule checks the schedule once a second until ctx ends.
func (c *Core) runMorningSchedule(ctx context.Context) {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			c.tickMorning()
		}
	}
}

// tickMorning raises the morning reminder when the timer is idle and the
// schedule is due. It reads the timer before touching the reminder, keeping
// the lock order timer then reminder.
func (c *Core) tickMorning() {
	if c.timer.State() != engine.Idle {
		return
	}
	if c.reminder.shouldRaiseMorning(c.now(), c.scheduler) {
		c.reminder.raise(reminderMorning)
	}
}
