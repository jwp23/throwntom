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

// Ack says the reminder was answered, so it stops even the first alert: there
// is nothing left to alert anyone about. That is what separates it from
// cancelling Run's ctx, which only retires this loop and still owes the alert
// the loop was started to make. The two are not interchangeable — a caller
// that means "stop ringing" wants the ctx, and acking there silences a loop
// whose goroutine has not been scheduled yet.
func (l *Loop) Ack() {
	l.acked.Store(true)
}

// Run alerts on the policy's cadence until it is acked, its ctx is cancelled
// or the policy's bound is reached. The first alert is checked against acked
// but deliberately not against ctx: an answered reminder has nothing to say,
// while a retired one still made the alert it was started for, and which of
// those happened must not depend on when this goroutine was scheduled.
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
