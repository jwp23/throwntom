package core

// Subscribe returns a channel that receives the current State immediately and
// a fresh State after every change. The channel holds one value; when the
// subscriber is slow the newest State replaces the undelivered one. The
// returned func stops delivery and closes the channel.
func (c *Core) Subscribe() (<-chan State, func()) {
	ch := make(chan State, 1)
	c.mu.Lock()
	// Registering and seeding under the lock keeps the first value in step with
	// the fan-out: the buffer is empty and unshared, so the send cannot block.
	c.subscribers[ch] = struct{}{}
	ch <- c.stateLocked()
	c.mu.Unlock()

	cancel := func() {
		c.mu.Lock()
		defer c.mu.Unlock()
		if _, ok := c.subscribers[ch]; ok {
			delete(c.subscribers, ch)
			close(ch)
		}
	}
	return ch, cancel
}

// publish serialises one save and fan-out on publishMu.
// Callers must not hold c.mu (State takes it), so verbs do their work under
// the lock, release it, then publish. publishAsync is required whenever a
// callback runs while c.mu is already held — pomodoro.Timer's onTransition
// and the raise/cancel it drives fire that way, and a synchronous publish
// there would deadlock on State's own lock. Other callbacks, such as
// outstandingReminder.resume firing from its snooze timer, run without c.mu
// held; publishAsync is harmless there too, so every callback goes through it.
//
// publishMu serialises publishes: a State is read and delivered while it is
// held, so a subscriber never receives a State older than one it already got.
// Stop holds it too, which is how it can end publishing for good.
func (c *Core) publish() {
	c.publishMu.Lock()
	defer c.publishMu.Unlock()
	c.saveAndFanOut()
}

// saveAndFanOut snapshots State, saves the session and hands the snapshot to
// every subscriber. Callers must hold publishMu and must not hold c.mu; the
// lock order is publishMu then c.mu.
func (c *Core) saveAndFanOut() {
	s := c.State()
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.stopped {
		return
	}
	c.saveSessionLocked()
	for ch := range c.subscribers {
		select {
		case <-ch: // drop the stale value the subscriber has not read yet
		default:
		}
		ch <- s
	}
}

// publishAsync publishes on its own goroutine, for callers that hold c.mu.
func (c *Core) publishAsync() {
	go c.publish()
}
