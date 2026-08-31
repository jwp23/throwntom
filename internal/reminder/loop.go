package reminder

import (
	"context"
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
}

func New(policy Policy, notify func() error) *Loop {
	if policy.Interval <= 0 || policy.MaxAlerts < 1 {
		policy.MaxAlerts = 1
	}
	return &Loop{policy: policy, notify: notify}
}

// Run alerts on the policy's cadence until its ctx is cancelled or the
// policy's bound is reached. Cancelling the ctx is the only way a caller
// retires a loop, and it deliberately does not reach the first alert: a
// retired loop still made the alert it was started for, and whether the user
// hears it must not depend on when this goroutine was scheduled.
//
// Answering a reminder is not this type's business. The outstanding reminder
// owns that (ADR-004): an answer is a transition, and leaving the state that
// owed the nudge is what retires it — see Core.onTransition in
// internal/core/core.go. Whether a later alert still counts is likewise the
// owner's call, decided in outstandingReminder.ring, not the loop's.
func (l *Loop) Run(ctx context.Context) {
	_ = l.notify()
	alerts := 1
	if alerts >= l.policy.MaxAlerts {
		return
	}
	ticker := time.NewTicker(l.policy.Interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			_ = l.notify()
			alerts++
			if alerts >= l.policy.MaxAlerts {
				return
			}
		}
	}
}
