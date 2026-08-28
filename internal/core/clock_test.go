package core

import (
	"sort"
	"sync"
	"time"
)

// fakeClock is a manually advanced clock and timer factory. Tests point a
// reminder's now and after at it and move time with Advance so deadlines fire
// at exact durations instead of within wall-clock margins.
type fakeClock struct {
	mu      sync.Mutex
	now     time.Time
	pending []*fakeTimer
}

type fakeTimer struct {
	clock  *fakeClock
	fireAt time.Time
	fn     func()
}

func newFakeClock(start time.Time) *fakeClock {
	return &fakeClock{now: start}
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) After(d time.Duration, fn func()) stopper {
	c.mu.Lock()
	defer c.mu.Unlock()
	t := &fakeTimer{clock: c, fireAt: c.now.Add(d), fn: fn}
	c.pending = append(c.pending, t)
	return t
}

// Advance moves the clock forward and runs every callback that comes due, in
// fire order. Callbacks run without the clock lock held.
func (c *fakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	c.now = c.now.Add(d)
	var due []*fakeTimer
	remaining := c.pending[:0]
	for _, t := range c.pending {
		if t.fireAt.After(c.now) {
			remaining = append(remaining, t)
			continue
		}
		due = append(due, t)
	}
	c.pending = remaining
	c.mu.Unlock()

	sort.SliceStable(due, func(i, j int) bool { return due[i].fireAt.Before(due[j].fireAt) })
	for _, t := range due {
		t.fn()
	}
}

func (t *fakeTimer) Stop() bool {
	c := t.clock
	c.mu.Lock()
	defer c.mu.Unlock()
	for i, pending := range c.pending {
		if pending == t {
			c.pending = append(c.pending[:i], c.pending[i+1:]...)
			return true
		}
	}
	return false
}
