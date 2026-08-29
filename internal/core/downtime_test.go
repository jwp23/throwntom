package core

// A phase counts wall-clock time through daemon downtime: ADR-006 (2). These
// tests pin that as a decision rather than an accident of storing an absolute
// phase_end_at.

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/pomodoro"
	"github.com/jwp23/throwntom/v3/internal/session"
)

// restoreFrom builds a Core whose session file holds a work phase ending at
// phaseEndAt, the way a daemon that went down mid-phase left it.
func restoreFrom(t *testing.T, phaseEndAt time.Time) *Core {
	t.Helper()
	sessPath := filepath.Join(t.TempDir(), testSessionFile)
	data := session.Data{
		SavedAt: time.Now(),
		Timer: pomodoro.Snapshot{
			Engine: engine.Snapshot{
				State:          engine.Work,
				LastPhase:      engine.Work,
				WorkDayStarted: true,
				WorkDate:       time.Now(),
			},
			PhaseEndAt: phaseEndAt,
		},
	}
	if err := session.Save(sessPath, data); err != nil {
		t.Fatal(err)
	}
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.sessionPath = sessPath
	if err := c.loadSession(); err != nil {
		t.Fatalf(fmtLoadSession, err)
	}
	return c
}

func TestRestoredPhaseKeepsCountingThroughDowntime(t *testing.T) {
	c := restoreFrom(t, time.Now().Add(10*time.Minute))
	defer c.Stop()

	state := c.State()
	if state.State != engine.Work {
		t.Fatalf("expected the work phase to resume, got %s", state.State)
	}
	remaining := time.Until(*state.PhaseEndAt)
	// The phase keeps its original end time: 15 of a 25-minute pomodoro were
	// spent before the daemon stopped, and they are not given back.
	if remaining > 10*time.Minute || remaining < 9*time.Minute {
		t.Fatalf("expected roughly 10m of the original phase left, got %s", remaining)
	}
}

func TestPhaseThatExpiredWhileTheDaemonWasDownEndsOnRestore(t *testing.T) {
	c := restoreFrom(t, time.Now().Add(-time.Hour))
	defer c.Stop()

	state := c.State()
	if state.State != engine.AwaitingConfirm {
		t.Fatalf("expected a phase that ran out during downtime to be complete, got %s", state.State)
	}
	if state.CompletedToday != 1 {
		t.Fatalf("expected the pomodoro to count once, got %d", state.CompletedToday)
	}
}
