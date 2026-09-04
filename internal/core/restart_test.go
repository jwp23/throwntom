package core

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/config"
)

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
