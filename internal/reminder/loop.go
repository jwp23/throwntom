package reminder

import (
	"context"
	"sync/atomic"
	"time"
)

// Policy is how often a reminder alerts and how many alerts it may make in
// total. The bound is what stops a reminder nobody is around to acknowledge:
// without it the loop keeps alerting for as long as the process lives.
type Policy struct {
	Interval  time.Duration
	MaxAlerts int
}

// NewPolicy spreads alerts an interval apart across at most limit of wall
// time. Every policy allows at least the first alert, so a nonsensical
// interval or limit silences the reminder rather than unbounding it.
func NewPolicy(interval, limit time.Duration) Policy {
	p := Policy{Interval: interval, MaxAlerts: 1}
	if interval > 0 && limit > 0 {
		p.MaxAlerts = 1 + int(limit/interval)
	}
	return p
}

type Loop struct {
	policy Policy
	notify func() error
	acked  atomic.Bool
}

func New(policy Policy, notify func() error) *Loop {
	if policy.Interval <= 0 || policy.MaxAlerts < 1 {
		policy.MaxAlerts = 1
	}
	return &Loop{policy: policy, notify: notify}
}

func (l *Loop) Ack() {
	l.acked.Store(true)
}

func (l *Loop) Run(ctx context.Context) {
	if l.acked.Load() {
		return
	}
	_ = l.notify()
	alerts := 1
	if l.acked.Load() || alerts >= l.policy.MaxAlerts {
		return
	}
	ticker := time.NewTicker(l.policy.Interval)
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
			alerts++
			if alerts >= l.policy.MaxAlerts {
				return
			}
		}
	}
}
