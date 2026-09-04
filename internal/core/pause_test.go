package core

import (
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
)

// The threshold is short enough that the watchdog fires while the test waits,
// and long enough that a pause and a resume in the same breath still beat it.
const testPauseThreshold = 20 * time.Millisecond

func TestThePauseThresholdComesFromTheConfig(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.PausedTooLongMinutes = 7
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()

	if got := c.timer.PausedTooLongAfter(); got != 7*time.Minute {
		t.Fatalf("the timer measures a pause against %s, want 7m", got)
	}
}

// The threshold passing is a change with no verb behind it, so the state that
// carries it has to arrive on its own.
func TestAPauseThatLastsTooLongIsPublished(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()
	c.timer.SetPausedTooLongAfter(testPauseThreshold)
	c.Execute(cmdStart)

	states, unsubscribe := c.Subscribe()
	defer unsubscribe()
	c.Execute("pause")

	deadline := time.After(2 * time.Second)
	for {
		select {
		case state := <-states:
			if state.PausedTooLong {
				return
			}
		case <-deadline:
			t.Fatal("no published state reported the pause as too long")
		}
	}
}

func TestAPauseResumedInTimeIsNeverTooLong(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	defer c.Stop()
	c.timer.SetPausedTooLongAfter(testPauseThreshold)
	c.Execute(cmdStart)
	c.Execute("pause")
	c.Execute("resume")

	time.Sleep(4 * testPauseThreshold)

	if c.State().PausedTooLong {
		t.Fatal("a pause the user resumed in time was reported as too long")
	}
}
