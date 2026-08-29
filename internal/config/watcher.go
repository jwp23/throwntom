package config

import (
	"bytes"
	"context"
	"os"
	"time"
)

// DefaultWatchInterval is how often a Watcher looks at the config file. The
// file is a few kilobytes and read at most once per interval, so the cost is
// negligible, while two seconds is short enough that an edit feels immediate.
const DefaultWatchInterval = 2 * time.Second

// Watcher reports changes to a config file. It polls rather than subscribing
// to filesystem events: the standard library has no portable watch API, and
// this daemon must build the same way on every OS it runs on.
type Watcher struct {
	// Path is the config file to watch. It need not exist yet; a file
	// created later is picked up like any other change.
	Path string
	// Interval is the poll period. Zero means DefaultWatchInterval.
	Interval time.Duration
	// OnChange receives the new config every time the file's contents change
	// and parse. It runs on the Watcher's own goroutine, so a slow OnChange
	// delays the next poll rather than racing it.
	OnChange func(Config)
	// OnError receives a config that changed but could not be read or
	// parsed. Nothing is applied for it; the last good config stays in force.
	OnError func(error)
}

// Run polls until ctx ends, measuring change against baseline: the file
// contents the caller already has in force. Taking the baseline as an
// argument rather than reading it here is what makes an edit made right after
// Run starts impossible to lose — the caller reads it before the goroutine
// exists. A nil baseline means nothing is in force yet, so the first poll
// reports whatever the file holds.
func (w Watcher) Run(ctx context.Context, baseline []byte) {
	interval := w.Interval
	if interval <= 0 {
		interval = DefaultWatchInterval
	}
	previous := baseline
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			previous = w.poll(previous)
		}
	}
}

// poll reports a changed file and returns the contents to compare next time.
// Contents, not modification time, decide: a rewrite with identical bytes is
// not a change the user made, and file timestamps are too coarse to catch two
// edits in the same second.
func (w Watcher) poll(previous []byte) []byte {
	current, err := os.ReadFile(w.Path)
	if err != nil {
		if os.IsNotExist(err) {
			return previous
		}
		w.reportError(err)
		return previous
	}
	if bytes.Equal(current, previous) {
		return previous
	}
	cfg, err := LoadBytes(current)
	if err != nil {
		w.reportError(err)
		// The bad contents become the baseline: the user is mid-edit, and
		// re-reporting the same broken file every interval helps nobody.
		return current
	}
	if w.OnChange != nil {
		w.OnChange(cfg)
	}
	return current
}

func (w Watcher) reportError(err error) {
	if w.OnError != nil {
		w.OnError(err)
	}
}
