package core

import (
	"io"
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

// setClock points the Core and its reminder at clk for both the current time
// and deadline scheduling.
func (c *Core) setClock(clk *fakeClock) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = clk.Now
	c.reminder.now = clk.Now
	c.reminder.after = clk.After
}

// setWarnOut redirects session warnings under the Core lock, so a test can
// capture and assert on one instead of letting it leak to stderr.
func (c *Core) setWarnOut(w io.Writer) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.warnOut = w
}

// setFocused replaces the focused task list under the Core lock, so tests can
// seed focus while background publishes are in flight.
func (c *Core) setFocused(focused []task.Task) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.focused = focused
}

// subscribeSync registers ch as a subscriber without seeding it. Tests pass an
// unbuffered channel, so every fan-out hands its State straight to a receiver
// and the test can order itself against publishes. The returned func
// unregisters ch.
func (c *Core) subscribeSync(ch chan State) func() {
	c.mu.Lock()
	c.subscribers[ch] = struct{}{}
	c.mu.Unlock()
	return func() {
		c.mu.Lock()
		defer c.mu.Unlock()
		delete(c.subscribers, ch)
	}
}

// saveSession saves the session under the Core lock, the way publish does.
func (c *Core) saveSession() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.saveSessionLocked()
}
