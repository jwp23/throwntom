package reminder

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

// Cancelling the context is how a loop is retired: the owner of the
// outstanding reminder holds that ctx and treats it as the loop's identity
// (ADR-004; internal/core/outstanding.go loopNotify).
func TestLoopRepeatsUntilItsContextIsCancelled(t *testing.T) {
	var count atomic.Int32
	// The bound is set far out of reach so that cancellation is the only thing
	// that can end this loop; a bound the test could reach would pass even if
	// Run ignored its ctx entirely.
	loop := New(Policy{Interval: 20 * time.Millisecond, MaxAlerts: 1_000_000}, func() error {
		count.Add(1)
		return nil
	})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	go func() {
		loop.Run(ctx)
		close(done)
	}()

	time.Sleep(70 * time.Millisecond)
	if repeats := count.Load(); repeats < 2 {
		t.Fatalf("expected the loop to repeat, got %d alerts", repeats)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("loop kept running after its context was cancelled")
	}
	got := count.Load()
	time.Sleep(50 * time.Millisecond)
	if now := count.Load(); now != got {
		t.Fatalf("expected no alerts after cancellation, got %d more", now-got)
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
