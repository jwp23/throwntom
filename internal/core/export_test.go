package core

import "time"

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
