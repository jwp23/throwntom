package core

import (
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/eventlog"
)

func TestMeetingCommandStartsAMeetingOfTheLengthGiven(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})

	result := c.execute("meeting 30")

	if result.err != nil {
		t.Fatalf("meeting refused: %v", result.err)
	}
	if c.timer.State() != engine.Meeting {
		t.Fatalf("state is %s, want meeting", c.timer.State())
	}
	assertPhaseLength(t, c, 30*time.Minute)
	if !strings.Contains(strings.ToLower(result.message), "meeting") {
		t.Fatalf("message %q does not name the meeting", result.message)
	}
}

// The length is written the way snooze's is: a bare number means minutes, and
// a duration with a unit is taken as written.
func TestMeetingAcceptsTheSameDurationFormsSnoozeDoes(t *testing.T) {
	for _, tc := range []struct {
		line string
		want time.Duration
	}{
		{"meeting 45", 45 * time.Minute},
		{"meeting 90m", 90 * time.Minute},
		{"meeting 1h", time.Hour},
	} {
		cfg := config.Default()
		cfg.MorningReminderPending = false
		c := newCore(cfg, noopNotifier{})

		if result := c.execute(tc.line); result.err != nil {
			t.Fatalf("%q refused: %v", tc.line, result.err)
		}
		assertPhaseLength(t, c, tc.want)
	}
}

func TestMeetingWithoutALengthIsRefused(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})

	result := c.execute("meeting")

	if result.err == nil {
		t.Fatal("a meeting with no length was accepted")
	}
	if !strings.Contains(result.err.Error(), "usage: meeting") {
		t.Fatalf("error %q does not say how to write the command", result.err)
	}
	if c.timer.State() == engine.Meeting {
		t.Fatal("a refused meeting started anyway")
	}
}

func TestMeetingOfNoLengthIsRefused(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c := newCore(cfg, noopNotifier{})

	if result := c.execute("meeting 0"); result.err == nil {
		t.Fatal("a zero-length meeting was accepted")
	}
	if result := c.execute("meeting -10"); result.err == nil {
		t.Fatal("a negative-length meeting was accepted")
	}
}

// The credit a meeting earns has to reach the event log, or the dashboard
// silently disagrees with the count in the window.
func TestAFinishedMeetingLogsTheCreditItEarned(t *testing.T) {
	c, path := newCoreWithEvents(t)

	c.execute("meeting 60")
	c.timer.CompletePeriod()
	c.execute("confirm")

	events := readEvents(t, path)
	ev, ok := findEvent(events, "meeting_completed")
	if !ok {
		t.Fatalf("no meeting_completed in %v", eventTypesOf(events))
	}
	if got := ev.Data["pomodoros"]; got != float64(2) {
		t.Fatalf("logged %v pomodoros, want 2", got)
	}
	if got := ev.Data["minutes"]; got != float64(60) {
		t.Fatalf("logged %v minutes, want 60", got)
	}
}

// Ending a meeting early is not skipping it: the time was spent, so it is
// credited and the log must not record it as a phase that was thrown away.
// What the credit comes to is settled at the timer, which owns the clock.
func TestEndingAMeetingEarlyIsNotLoggedAsASkip(t *testing.T) {
	c, path := newCoreWithEvents(t)

	c.execute("meeting 60")
	result := c.execute("skip")
	c.execute("confirm")

	events := readEvents(t, path)
	if hasEventType(events, "skipped") {
		t.Fatalf("ending a meeting was logged as a skip: %v", eventTypesOf(events))
	}
	if !hasEventType(events, "meeting_completed") {
		t.Fatalf("no meeting_completed in %v", eventTypesOf(events))
	}
	if strings.Contains(strings.ToLower(result.message), "skipped") {
		t.Fatalf("message %q calls ending a meeting a skip", result.message)
	}
}

// A meeting displaces a pomodoro waiting to be confirmed. The engine counted
// that pomodoro when it finished, so the log has to record it too.
func TestMeetingCreditsThePomodoroItDisplaces(t *testing.T) {
	c, path := newCoreWithEvents(t)
	c.execute(cmdStart)
	c.timer.CompletePeriod()

	c.execute("meeting 30")

	if !hasEventType(readEvents(t, path), "pomodoro_completed") {
		t.Fatal("the displaced pomodoro was not credited")
	}
}

// A meeting is not a break, so it must not be logged as one: the dashboard
// reads break events and pomodoro events differently.
func TestAMeetingIsNotLoggedAsABreak(t *testing.T) {
	c, path := newCoreWithEvents(t)

	c.execute("meeting 30")
	c.timer.CompletePeriod()
	c.execute("confirm")

	events := readEvents(t, path)
	if hasBreakKind(events, "break_started", "meeting") {
		t.Fatal("a meeting was logged as a break starting")
	}
	if hasBreakKind(events, "break_completed", "meeting") {
		t.Fatal("a meeting was logged as a break completing")
	}
}

func TestTheWindowNamesAMeeting(t *testing.T) {
	if got := FriendlyStateName(engine.Meeting); got != "meeting" {
		t.Fatalf("friendly name is %q, want %q", got, "meeting")
	}
}

func TestHelpListsMeeting(t *testing.T) {
	if !strings.Contains(Help(), "meeting") {
		t.Fatal("help does not list the meeting command")
	}
}

func findEvent(events []eventlog.Event, typ string) (eventlog.Event, bool) {
	for _, ev := range events {
		if ev.Type == typ {
			return ev, true
		}
	}
	return eventlog.Event{}, false
}

func eventTypesOf(events []eventlog.Event) []string {
	types := make([]string, 0, len(events))
	for _, ev := range events {
		types = append(types, ev.Type)
	}
	return types
}
