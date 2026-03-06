package reminder

import (
	"context"
	"sync/atomic"
	"time"
)

type Loop struct {
	interval time.Duration
	notify   func() error
	acked    atomic.Bool
}

func New(interval time.Duration, notify func() error) *Loop {
	return &Loop{interval: interval, notify: notify}
}

func (l *Loop) Ack() {
	l.acked.Store(true)
}

func (l *Loop) Run(ctx context.Context) {
	if l.acked.Load() {
		return
	}
	_ = l.notify()
	if l.acked.Load() {
		return
	}
	ticker := time.NewTicker(l.interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if l.acked.Load() {
				return
			}
			_ = l.notify()
		}
	}
}
