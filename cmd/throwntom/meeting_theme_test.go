package main

import (
	"testing"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// A meeting is credited work, so it wears work's colour rather than a hue of
// its own; the state text beside it is what names it. This is the same rule
// lunch follows against the long break.

func TestMeetingWearsTheWorkColour(t *testing.T) {
	meeting := stateStyle(engine.Meeting).GetForeground()
	work := stateStyle(engine.Work).GetForeground()
	if meeting != work {
		t.Fatalf("meeting is %v, want work's %v", meeting, work)
	}
}

func TestMeetingHasItsOwnEmojiIcon(t *testing.T) {
	icon := stateIcon(engine.Meeting, true)
	if icon == "" {
		t.Fatal("meeting has no emoji icon")
	}
	for _, other := range []engine.State{engine.Work, engine.ShortBreak, engine.LongBreak, engine.Lunch, engine.Idle, engine.Paused, engine.AwaitingConfirm} {
		if icon == stateIcon(other, true) {
			t.Fatalf("meeting shares the %s emoji, so the two states read alike", other)
		}
	}
}

// The ASCII set groups states by what they are: every rest wears `~`, and a
// meeting is work, so it wears work's mark.
func TestMeetingWearsWorksAsciiIcon(t *testing.T) {
	if got, want := stateIcon(engine.Meeting, false), stateIcon(engine.Work, false); got != want {
		t.Fatalf("meeting's ascii icon is %q, want work's %q", got, want)
	}
}
