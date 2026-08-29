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
	state := watchState{applied: baseline, seen: baseline}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			state = w.poll(state)
		}
	}
}

// watchState is what the watcher remembers between polls: the contents it
// last put in force, the contents it last read, and the error it last
// reported.
type watchState struct {
	applied   []byte
	seen      []byte
	lastError string
}

// poll reports a settled change and returns the state to carry forward.
//
// Contents, not modification time, decide what changed: a rewrite with
// identical bytes is not a change the user made, and file timestamps are too
// coarse to catch two edits in the same second.
//
// A change must hold still for one poll before it is applied. Writing a file
// is not atomic — most editors, and os.WriteFile itself, truncate before they
// write — so a poll can land on an empty or half-written file. An empty
// config is not an error, it parses as every default, so applying one would
// silently replace the user's durations and could end the running phase.
// Waiting for the same bytes twice costs one interval and rules that out.
func (w Watcher) poll(state watchState) watchState {
	current, err := os.ReadFile(w.Path)
	if err != nil {
		if !os.IsNotExist(err) {
			state.lastError = w.reportError(err, state.lastError)
		}
		return state
	}
	if !bytes.Equal(current, state.seen) {
		state.seen = current
		return state
	}
	if bytes.Equal(current, state.applied) {
		return state
	}
	cfg, err := LoadBytes(current)
	if err != nil {
		state.lastError = w.reportError(err, state.lastError)
		// The bad contents count as applied: the user is mid-edit, and
		// re-reporting the same broken file every interval helps nobody.
		state.applied = current
		return state
	}
	state.lastError = ""
	state.applied = current
	if w.OnChange != nil {
		w.OnChange(cfg)
	}
	return state
}

// reportError passes err on unless it repeats the last one, so a config the
// daemon cannot read does not fill the log with the same line every interval.
// It returns the error now considered reported.
func (w Watcher) reportError(err error, last string) string {
	if err.Error() == last {
		return last
	}
	if w.OnError != nil {
		w.OnError(err)
	}
	return err.Error()
}
