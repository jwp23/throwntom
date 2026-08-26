package core

import (
	"time"

	"github.com/jwp23/throwntom/v3/internal/task"
)

// execute runs one command the way Execute does, holding the Core lock. Tests
// use it to drive the command handlers without going through the Response and
// publish machinery.
func (c *Core) execute(line string) commandResult {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.executeLocked(line)
}

// setNow replaces the Core clock under the Core lock, so tests can move time
// while background publishes are in flight.
func (c *Core) setNow(fn func() time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = fn
}

// setFocused replaces the focused task list under the Core lock, so tests can
// seed focus while background publishes are in flight.
func (c *Core) setFocused(focused []task.Task) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.focused = focused
}

// saveSession saves the session under the Core lock, the way publish does.
func (c *Core) saveSession() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.saveSessionLocked()
}
