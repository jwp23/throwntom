package core

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/session"
)

func recv(t *testing.T, ch <-chan State) State {
	t.Helper()
	select {
	case s, ok := <-ch:
		if !ok {
			t.Fatal("channel closed")
		}
		return s
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for state")
	}
	return State{}
}

func TestSubscribeDeliversInitialAndExecuteStates(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	ch, cancel := c.Subscribe()
	defer cancel()

	if s := recv(t, ch); s.State != engine.Idle {
		t.Fatalf("initial state = %s", s.State)
	}
	c.Execute("new-cycle")
	if s := recv(t, ch); s.State != engine.Work {
		t.Fatalf("after start = %s", s.State)
	}
}

func TestSubscribeDeliversTimerExpiry(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = filepath.Join(t.TempDir(), "session.json")
	defer c.Stop()
	ch, cancel := c.Subscribe()
	defer cancel()
	recv(t, ch)

	beforeExpiry := time.Now()
	snap := c.timer.Snapshot()
	snap.Engine.State = engine.Work
	snap.PhaseEndAt = time.Now().Add(20 * time.Millisecond)
	if err := c.timer.Restore(snap, time.Now()); err != nil {
		t.Fatal(err)
	}
	deadline := time.After(2 * time.Second)
	for done := false; !done; {
		select {
		case s := <-ch:
			if s.State == engine.AwaitingConfirm {
				done = true
			}
		case <-deadline:
			t.Fatal("never saw awaiting_confirm after timer expiry")
		}
	}

	data, err := session.Load(c.sessionPath)
	if err != nil {
		t.Fatalf("load session: %v", err)
	}
	if !data.SavedAt.After(beforeExpiry) {
		t.Fatalf("expected session saved after expiry, saved_at = %s", data.SavedAt)
	}
	if data.Timer.Engine.State != engine.AwaitingConfirm {
		t.Fatalf("expected saved session in awaiting_confirm, got %s", data.Timer.Engine.State)
	}
}

func TestSubscribeLatestWinsForSlowSubscriber(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	ch, cancel := c.Subscribe()
	defer cancel()

	c.Execute("new-cycle")
	c.Execute("pause")
	c.Execute("resume")
	c.Execute("pause") // four publishes, nobody reading: must not block
	if s := recv(t, ch); s.State != engine.Paused {
		t.Fatalf("expected latest state paused, got %s", s.State)
	}
}

func TestSubscribeCancelClosesChannel(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	ch, cancel := c.Subscribe()
	recv(t, ch)
	cancel()
	if _, ok := <-ch; ok {
		t.Fatal("expected closed channel after cancel")
	}
	c.Execute("new-cycle") // must not panic on the removed subscriber
}

func TestSubscribeDeliversMorningPending(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	ch, cancel := c.Subscribe()
	defer cancel()
	recv(t, ch)

	c.reminder.raise(reminderMorning)
	if s := recv(t, ch); !s.MorningPending {
		t.Fatal("expected morning_pending after loop start")
	}
	c.reminder.cancel()
	if s := recv(t, ch); s.MorningPending {
		t.Fatal("expected morning_pending cleared after loop stop")
	}
}

func TestSubscribeDoesNotSelfTrigger(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	ch, cancel := c.Subscribe()
	defer cancel()
	recv(t, ch)

	for i := 0; i < 10; i++ {
		c.State()
	}
	select {
	case s := <-ch:
		t.Fatalf("reading state published a change: %s", s.State)
	case <-time.After(200 * time.Millisecond):
	}
}

func TestStopPublishesOnce(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	ch, cancel := c.Subscribe()
	defer cancel()
	recv(t, ch)

	c.Stop()
	recv(t, ch)
	select {
	case s := <-ch:
		t.Fatalf("Stop published more than once: %s", s.State)
	case <-time.After(200 * time.Millisecond):
	}
}

func TestSubscribeAfterStop(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.Stop()

	ch, cancel := c.Subscribe()
	defer cancel()
	if s := recv(t, ch); s.State != engine.Idle {
		t.Fatalf("state after stop = %s", s.State)
	}
}

func TestSubscribeConcurrentCallers(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	ch, cancel := c.Subscribe()
	defer cancel()

	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < 50; i++ {
			c.Execute("status")
			c.State()
		}
	}()
	for i := 0; i < 50; i++ {
		c.Status()
		c.Focused()
		c.FocusPromptPending()
	}
	<-done
	recv(t, ch)
}

func TestPublishSuppressedAfterStop(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = filepath.Join(t.TempDir(), "session.json")
	ch, cancel := c.Subscribe()
	defer cancel()
	recv(t, ch)

	c.Stop()
	recv(t, ch) // Stop's own publish

	c.timer.Start() // a late change must neither reach subscribers nor save
	select {
	case s := <-ch:
		t.Fatalf("published after Stop: %s", s.State)
	case <-time.After(200 * time.Millisecond):
	}
	c.timer.Stop()
}

// stopWindowWait bounds the wait for a publish that starts inside Stop's
// window. Stop must shut that publish out, so the wait is expected to expire.
const stopWindowWait = 100 * time.Millisecond

// TestStopShutsOutPublishInFinalWindow forces the interleaving Stop's contract
// forbids: a publish begins after the final publish delivered and before Stop
// returns. It must neither save the session nor reach a subscriber. The
// afterFinalPublish seam makes the ordering deterministic instead of hoping a
// background goroutine lands in the window.
func TestStopShutsOutPublishInFinalWindow(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = filepath.Join(t.TempDir(), testSessionFile)

	stopAt := time.Date(2026, 3, 4, 10, 0, 0, 0, time.Local)
	lateAt := stopAt.Add(time.Hour)
	c.setNow(func() time.Time { return stopAt })

	sub := make(chan State)
	unsubscribe := c.subscribeSync(sub)
	delivered := make(chan State, 2)
	drained := make(chan struct{})
	go func() {
		defer close(drained)
		for s := range sub {
			delivered <- s
		}
	}()

	latePublished := make(chan struct{})
	c.afterFinalPublish = func() {
		<-delivered // the final publish reached the subscriber
		c.setNow(func() time.Time { return lateAt })
		go func() {
			defer close(latePublished)
			c.publish() // exactly what a queued publishAsync runs
		}()
		select {
		case s := <-delivered:
			t.Errorf("publish reached a subscriber inside Stop's window: %s", s.State)
		case <-time.After(stopWindowWait):
		}
	}

	c.Stop()
	<-latePublished
	unsubscribe()
	close(sub)
	<-drained

	data, err := session.Load(c.sessionPath)
	if err != nil {
		t.Fatalf("load session: %v", err)
	}
	if !data.SavedAt.Equal(stopAt) {
		t.Fatalf("session saved inside Stop's window: saved_at = %s, want %s", data.SavedAt, stopAt)
	}
}

func TestSubscriberSeesCycleSnoozeExpire(t *testing.T) {
	c, rec, clk := awaitingCore(t)
	waitForSounds(t, rec, 1)
	ch := make(chan State, 8)
	unsubscribe := c.subscribeSync(ch)
	defer unsubscribe()

	if result := c.execute("snooze 5m"); result.err != nil {
		t.Fatalf(fmtSnoozeFailed, result.err)
	}
	c.publish()
	seen := <-ch
	if seen.SnoozeUntil == nil {
		t.Fatal("expected the snooze deadline to be published")
	}
	clk.Advance(5 * time.Minute)
	deadline := time.After(2 * time.Second)
	for {
		select {
		case s := <-ch:
			if s.SnoozeUntil == nil && s.State == engine.AwaitingConfirm {
				return
			}
		case <-deadline:
			t.Fatal("expected a published state with snooze_until null after expiry")
		}
	}
}
