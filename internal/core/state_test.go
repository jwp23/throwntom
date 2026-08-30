package core

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

func TestStateIdle(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})

	s := c.State()
	if s.State != engine.Idle || s.PhaseEndAt != nil || s.NextStage != nil || s.SnoozeUntil != nil {
		t.Fatalf("unexpected idle state %+v", s)
	}
	if s.LongBreakEvery != cfg.Pomodoro.LongBreakEvery {
		t.Fatalf("long_break_every = %d", s.LongBreakEvery)
	}
	if s.StatusLine == "" {
		t.Fatal("expected status line")
	}
}

func TestStateWorkHasPhaseEnd(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdStart)

	s := c.State()
	if s.State != engine.Work || s.PhaseEndAt == nil || !s.PhaseEndAt.After(time.Now()) {
		t.Fatalf("expected work with future phase end, got %+v", s)
	}
}

func TestStateAwaitingConfirmHasNextStage(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdStart)
	c.timer.CompletePeriod()

	s := c.State()
	if s.NextStage == nil || s.NextStage.State != engine.ShortBreak || s.NextStage.DurationSeconds != 300 {
		t.Fatalf("expected short break next stage, got %+v", s.NextStage)
	}
	if s.CompletedToday != 1 {
		t.Fatalf("completed_today = %d", s.CompletedToday)
	}
}

func TestStatePausedRemaining(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdStart)
	c.execute("pause")

	s := c.State()
	if s.State != engine.Paused || s.PausedRemaining < 1490 || s.PausedRemaining > 1500 {
		t.Fatalf("expected ~1500s paused remaining, got %+v", s)
	}
}

func TestStateSnoozeUntil(t *testing.T) {
	cfg := config.Default()
	c := newCore(cfg, noopNotifier{})
	c.reminder.raise(reminderMorning)
	defer c.reminder.cancel()
	c.execute("snooze 10")
	s := c.State()
	if s.SnoozeUntil == nil || !s.SnoozeUntil.After(time.Now().Add(9*time.Minute)) {
		t.Fatalf("expected snooze_until ~10m ahead, got %+v", s.SnoozeUntil)
	}
	if !s.MorningPending {
		t.Fatal("expected morning_pending true while the morning reminder is snoozed")
	}
}

func TestStatePausedFrom(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	if got := c.State().PausedFrom; got != engine.Idle {
		t.Fatalf("idle paused_from = %v, want idle", got)
	}
	c.execute(cmdStart)
	c.execute("pause")

	s := c.State()
	if s.State != engine.Paused || s.PausedFrom != engine.Work {
		t.Fatalf("expected paused from work, got state=%v paused_from=%v", s.State, s.PausedFrom)
	}
	raw, err := json.Marshal(s)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), `"paused_from":"work"`) {
		t.Fatalf("paused_from missing from %s", raw)
	}
}

func TestStateJSONTags(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	raw, err := json.Marshal(newCore(cfg, noopNotifier{}).State())
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{`"state":"idle"`, `"phase_end_at":null`, `"paused_remaining":0`, `"paused_from":"idle"`, `"completed_today":0`, `"work_sessions_in_block":0`, `"long_break_every":`, `"next_stage":null`, `"morning_pending":false`, `"snooze_until":null`, `"status_line":"`, `"focused_task_ids":`, `"reminder_rings":`, `"day_ended":false`} {
		if !strings.Contains(string(raw), key) {
			t.Fatalf("missing %s in %s", key, raw)
		}
	}
}

// The daemon plays no sound (ADR-007), so the repeat reaches the user only if
// the ring count reaches the client. State is the channel clients already
// read, so the count rides it.
func TestStatePublishesTheReminderRingCount(t *testing.T) {
	c := newTestCoreWithTasks(t)
	if got := c.State().ReminderRings; got != 0 {
		t.Fatalf("expected no rings before a reminder, got %d", got)
	}
	_ = c.reminder.ring()
	_ = c.reminder.ring()
	if got := c.State().ReminderRings; got != 2 {
		t.Fatalf("expected the published count to follow the rings, got %d", got)
	}
}

// The window needs to tell "idle, ready to go" from "idle, the user is done
// for the day"; morning_pending cannot, because it is false in both.
func TestStateReportsTheDayEndedAfterSkipToday(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	if c.State().DayEnded {
		t.Fatal("expected day_ended false before skip-today")
	}

	c.execute("skip-today")

	s := c.State()
	if !s.DayEnded {
		t.Fatalf("expected day_ended after skip-today, got %+v", s)
	}
	raw, err := json.Marshal(s)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), `"day_ended":true`) {
		t.Fatalf("day_ended missing from %s", raw)
	}
}

func TestStartingAgainClearsTheEndedDay(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute("skip-today")

	c.execute(cmdStart)

	if c.State().DayEnded {
		t.Fatal("expected day_ended cleared once work starts again")
	}
}
