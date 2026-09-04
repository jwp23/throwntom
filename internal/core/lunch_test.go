package core

import (
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/doctest"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/eventlog"
)

const cmdLunch = "lunch"

func TestLunchCommandStartsLunch(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})

	result := c.execute(cmdLunch)

	if result.err != nil {
		t.Fatalf("lunch refused: %v", result.err)
	}
	if c.timer.State() != engine.Lunch {
		t.Fatalf("state is %s, want lunch", c.timer.State())
	}
	if !strings.Contains(result.message, "Lunch") {
		t.Fatalf("message %q does not name lunch", result.message)
	}
}

func TestLunchRunsForTheConfiguredMinutes(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	cfg.Pomodoro.LunchMinutes = 45
	c := newCore(cfg, noopNotifier{})

	c.execute(cmdLunch)

	assertPhaseLength(t, c, 45*time.Minute)
}

// A reloaded lunch_minutes lands on a lunch already under way, the way every
// other phase length does.
func TestReloadAppliesLunchMinutesToARunningLunch(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdLunch)

	reloaded := cfg
	reloaded.Pomodoro.LunchMinutes = 30
	c.ApplyConfig(reloaded)

	assertPhaseLength(t, c, 30*time.Minute)
}

func TestLunchLogsItsOwnBreakKind(t *testing.T) {
	c, path := newCoreWithEvents(t)

	c.execute(cmdLunch)
	c.timer.CompletePeriod()
	c.execute("confirm")

	events := readEvents(t, path)
	if !hasBreakKind(events, "break_started", cmdLunch) {
		t.Fatalf("no break_started of kind lunch in %v", eventKinds(events))
	}
	if !hasBreakKind(events, "break_completed", cmdLunch) {
		t.Fatalf("no break_completed of kind lunch in %v", eventKinds(events))
	}
	if !hasEventType(events, "pomodoro_started") {
		t.Fatal("confirming out of lunch did not start a pomodoro")
	}
}

// Lunch displaces a pomodoro waiting to be confirmed. The engine counted that
// pomodoro when it finished, so the event log has to record it too or the
// dashboard silently loses one.
func TestLunchCreditsThePomodoroItDisplaces(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute(cmdStart)
	c.timer.CompletePeriod()

	c.execute(cmdLunch)

	if !hasEventType(readEvents(t, path), "pomodoro_completed") {
		t.Fatal("the displaced pomodoro was not credited")
	}
}

func TestHelpListsLunch(t *testing.T) {
	if !strings.Contains(Help(), cmdLunch) {
		t.Fatal("help does not list the lunch command")
	}
}

// The config template tells the reader that taking lunch ends the block. That
// is a claim about the engine, so it is checked against the engine here: the
// sentence and the behaviour fail together.
func TestTemplateSaysLunchEndsTheBlockAndItDoes(t *testing.T) {
	const claim = "taking it ends the current block, so the pomodoro you come back to is the first of a " +
		"fresh one and the long break is a whole block away again"
	if !strings.Contains(doctest.UnwrapComments(config.Template), claim) {
		t.Fatalf("the config template no longer says: %s", claim)
	}

	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})
	c.execute(cmdStart)
	for i := 0; i < cfg.Pomodoro.LongBreakEvery-1; i++ {
		c.timer.CompletePeriod()
		c.execute("confirm")
		c.timer.CompletePeriod()
		c.execute("confirm")
	}
	if got := c.timer.Snapshot().Engine.WorkSessions; got != cfg.Pomodoro.LongBreakEvery-1 {
		t.Fatalf("precondition: %d pomodoros in the block, want %d", got, cfg.Pomodoro.LongBreakEvery-1)
	}

	c.execute(cmdLunch)

	if got := c.timer.Snapshot().Engine.WorkSessions; got != 0 {
		t.Fatalf("the block still holds %d pomodoros after lunch, want 0", got)
	}
	c.timer.CompletePeriod()
	c.execute("confirm")
	c.timer.CompletePeriod()
	if next, _, _ := c.NextStage(); next != engine.ShortBreak {
		t.Fatalf("the break after the first post-lunch pomodoro is %s, want short_break", next)
	}
}

// assertPhaseLength checks how long the running phase lasts. The Core under
// test runs on the real clock, which ticks between the two reads that fix a
// phase's start and end, so the length is checked to the second.
func assertPhaseLength(t *testing.T, c *Core, want time.Duration) {
	t.Helper()
	snap := c.timer.Snapshot()
	got := snap.PhaseEndAt.Sub(snap.PhaseStartedAt).Round(time.Second)
	if got != want {
		t.Fatalf("the phase runs for %s, want %s", got, want)
	}
}

func hasBreakKind(events []eventlog.Event, typ, kind string) bool {
	for _, ev := range events {
		if ev.Type == typ && ev.Data["kind"] == kind {
			return true
		}
	}
	return false
}

func eventKinds(events []eventlog.Event) []string {
	var seen []string
	for _, ev := range events {
		seen = append(seen, ev.Type+"/"+asString(ev.Data["kind"]))
	}
	return seen
}

func asString(v any) string {
	s, _ := v.(string)
	return s
}
