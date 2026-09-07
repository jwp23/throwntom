package core

import (
	"context"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// runTicker turns the daemon's own clock once a second until ctx ends.
func (c *Core) runTicker(ctx context.Context) {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			c.tick()
		}
	}
}

// tick is one turn of the daemon's clock: it rolls the work day over as the
// boundary passes, and raises the morning reminder when the timer is idle and
// the schedule is due. It holds the core lock across the idle check and the
// raise, so a command cannot slip between them and start a pomodoro just as
// the tick decides to ring.
//
// Noticing the boundary is the tick's alone. Every other call to AdvanceDay
// hangs off something the user did, and overnight the user does nothing:
// clients are push-only, so a day ended at 2am would still be ended at nine
// with nothing to say otherwise (ADR-013). The advance publishes for itself
// when the day turns, which is what reaches those clients.
func (c *Core) tick() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.timer.AdvanceDay(c.now(), c.dayStart)
	if c.timer.State() != engine.Idle {
		return
	}
	now := c.now()
	if c.reminder.shouldRaiseMorning(now, c.scheduler.ShouldTrigger(now), c.dayStart) {
		c.reminder.raise(reminderMorning)
	}
}
