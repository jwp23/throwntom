package reminder

import (
	"context"
	"sync/atomic"
	"testing"
	"time"
)

func TestLoopRepeatsUntilAck(t *testing.T) {
	var count atomic.Int32
	loop := New(20*time.Millisecond, func() error {
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
