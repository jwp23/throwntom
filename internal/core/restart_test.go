package core

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

// restartAt loads sessPath into a fresh core and starts it, the way the daemon
// comes back up. The clock is the restart's wall time and cfg is the config the
// daemon was launched with, morning_reminder_pending included.
func restartAt(t *testing.T, cfg config.Config, sessPath string, clk *fakeClock) *Core {
	t.Helper()
	c := newCore(cfg, noopNotifier{})
	c.setClock(clk)
	c.sessionPath = sessPath
	if err := c.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	c.Start(ctx)
	t.Cleanup(func() { cancel(); c.Stop() })
	return c
}

// workTwoPomodoros drives c through two completed work periods and the short
// break between them, the way a morning of actual use does.
func workTwoPomodoros(c *Core) {
	c.Execute(cmdStart)
	c.timer.CompletePeriod()
	c.Execute("confirm")
	c.timer.CompletePeriod()
	c.Execute("confirm")
	c.timer.CompletePeriod()
}

// The day's tally is the user's record of what they did, and nothing about
// declaring the day over and then picking work back up unmakes two worked
// pomodoros. This is the 2026-09-03 incident: the count reached the window as
// zero while the event log still held both completions.
func TestStartingWorkAfterAnEndedDayKeepsTheDaysCount(t *testing.T) {
	sessPath := filepath.Join(t.TempDir(), testSessionFile)
	cfg := config.Default()
	cfg.MorningReminderPending = false

	c := newCore(cfg, noopNotifier{})
	c.setClock(mondayAt(10, 0))
	c.sessionPath = sessPath
	defer c.Stop()
	workTwoPomodoros(c)
	c.Execute("skip-today")
	c.saveSession()

	restarted := newCore(cfg, noopNotifier{})
	restarted.setClock(mondayAt(19, 0))
	restarted.sessionPath = sessPath
	defer restarted.Stop()
	if err := restarted.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	if status, _, _ := restarted.Status(); !strings.Contains(status, "Today: 2") {
		t.Fatalf("the restart alone lost the day's count: %s", status)
	}

	restarted.Execute(cmdStart)

	status, _, _ := restarted.Status()
	if !strings.Contains(status, "Today: 2") {
		t.Fatalf("expected the day's two pomodoros to survive, got %s", status)
	}
}

// The daemon is usually up when midnight arrives, so the rollover happens in
// a live engine and is then saved. A snapshot that lands unreachable is
// discarded whole on the next start, costing the user the phase in flight and
// the day's focused tasks; only the day's totals were meant to reset.
func TestSessionSurvivesAMidnightRollover(t *testing.T) {
	sessPath := filepath.Join(t.TempDir(), testSessionFile)
	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.RepeatSecs = 3600

	c := newCore(cfg, noopNotifier{})
	c.setClock(newFakeClock(time.Date(2026, 3, 5, 23, 50, 0, 0, time.Local)))
	c.sessionPath = sessPath
	c.Execute(cmdStart)
	c.timer.CompletePeriod()
	c.setClock(newFakeClock(time.Date(2026, 3, 6, 0, 5, 0, 0, time.Local)))
	c.Stop()

	restarted := newCore(cfg, noopNotifier{})
	restarted.setClock(newFakeClock(time.Date(2026, 3, 6, 9, 0, 0, 0, time.Local)))
	restarted.sessionPath = sessPath
	defer restarted.Stop()
	if err := restarted.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}

	if got := restarted.timer.State(); got != engine.AwaitingConfirm {
		t.Fatalf("the rollover session was discarded; state is %v", got)
	}
	if status, _, _ := restarted.Status(); !strings.Contains(status, statusTodayPomodoros0) {
		t.Fatalf("expected the new day's total to start at zero, got %s", status)
	}
}

// "Done for the day" is answered once, and restarting the daemon does not
// unask it. morning_reminder_pending is a config default, not a record of
// today, so start-up has to check what the day already knows before it rings.
func TestRestartIntoAnEndedDayRaisesNoMorningReminder(t *testing.T) {
	sessPath := filepath.Join(t.TempDir(), testSessionFile)
	cfg := config.Default()

	c := newCore(cfg, noopNotifier{})
	c.setClock(mondayAt(10, 0))
	c.sessionPath = sessPath
	defer c.Stop()
	c.Execute(cmdStart)
	c.Execute("skip-today")
	c.saveSession()

	restarted := restartAt(t, cfg, sessPath, mondayAt(19, 0))

	if got := restarted.reminder.outstanding(); got != reminderNone {
		t.Fatalf("the restart re-raised a reminder on a day the user ended: %v", got)
	}
}

// A day whose work has already begun is past what the morning reminder exists
// to nudge, so a restart while it is idle between phases must not ring it
// either. Only day_ended used to say the day was underway, and a stop leaves
// the engine idle with day_ended false.
func TestRestartIntoAStartedDayRaisesNoMorningReminder(t *testing.T) {
	sessPath := filepath.Join(t.TempDir(), testSessionFile)
	cfg := config.Default()

	c := newCore(cfg, noopNotifier{})
	c.setClock(mondayAt(10, 0))
	c.sessionPath = sessPath
	defer c.Stop()
	c.Execute(cmdStart)
	c.timer.CompletePeriod()
	c.Execute("stop")
	c.saveSession()

	restarted := restartAt(t, cfg, sessPath, mondayAt(19, 0))

	if got := restarted.reminder.outstanding(); got != reminderNone {
		t.Fatalf("the restart re-raised a reminder on a day already worked: %v", got)
	}
}
