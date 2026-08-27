package reminder

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

func TestLoopRepeatsUntilAck(t *testing.T) {
	var count atomic.Int32
	loop := New(Policy{Interval: 20 * time.Millisecond, MaxAlerts: 100}, func() error {
		count.Add(1)
		return nil
	})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go loop.Run(ctx)

	time.Sleep(70 * time.Millisecond)
	loop.Ack()
	got := count.Load()
	time.Sleep(50 * time.Millisecond)
	if count.Load() != got {
		t.Fatalf("expected no reminders after ack")
	}
}

func TestLoopStopsAtAlertBound(t *testing.T) {
	var count atomic.Int32
	loop := New(Policy{Interval: 5 * time.Millisecond, MaxAlerts: 3}, func() error {
		count.Add(1)
		return nil
	})
	done := make(chan struct{})
	go func() {
		loop.Run(context.Background())
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("loop kept alerting past its bound")
	}
	if got := count.Load(); got != 3 {
		t.Fatalf("expected 3 alerts, got %d", got)
	}
}

func TestLoopWithoutAnIntervalAlertsOnce(t *testing.T) {
	var count atomic.Int32
	loop := New(Policy{Interval: 0, MaxAlerts: 5}, func() error {
		count.Add(1)
		return nil
	})
	done := make(chan struct{})
	go func() {
		loop.Run(context.Background())
		close(done)
	}()

	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("loop with no interval never returned")
	}
	if got := count.Load(); got != 1 {
		t.Fatalf("expected a single alert, got %d", got)
	}
}

func TestNewPolicySpreadsAlertsOverTheLimit(t *testing.T) {
	tests := []struct {
		name      string
		interval  time.Duration
		limit     time.Duration
		wantAlert int
	}{
		{name: "limit is a multiple of the interval", interval: 20 * time.Second, limit: 5 * time.Minute, wantAlert: 16},
		{name: "limit shorter than the interval", interval: 20 * time.Second, limit: 5 * time.Second, wantAlert: 1},
		{name: "limit not a multiple of the interval", interval: 20 * time.Second, limit: 50 * time.Second, wantAlert: 3},
		{name: "no limit still alerts once", interval: 20 * time.Second, limit: 0, wantAlert: 1},
		{name: "no interval still alerts once", interval: 0, limit: 5 * time.Minute, wantAlert: 1},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewPolicy(tc.interval, tc.limit)
			if got.Interval != tc.interval {
				t.Fatalf("interval: got %v want %v", got.Interval, tc.interval)
			}
			if got.MaxAlerts != tc.wantAlert {
				t.Fatalf("max alerts: got %d want %d", got.MaxAlerts, tc.wantAlert)
			}
		})
	}
}
