package core

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/doctest"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

// The README's paragraph on meetings makes three claims about the daemon that
// no other test would catch going stale: the rounding a meeting's credit uses,
// the two worked examples of it, and that credits crossing the block boundary
// bring the long break with them. Each is checked against the daemon here, so
// the sentence and the behaviour fail together.
//
// The arithmetic is the part worth pinning: it is the one place where a reader
// can work out what they will be credited before it happens, and a rounding
// rule that quietly changed would be invisible until the day's total was wrong.
const readmeMeetingCreditClaim = "When it ends, its length is credited as pomodoros — rounded to the nearest, " +
	"with half rounding up, so a 60-minute meeting is worth 2 at the default 25-minute pomodoro and a " +
	"10-minute one is worth none."

const readmeMeetingBlockClaim = "Those credits count toward the day's total and toward the long break alike, " +
	"so a meeting earns the break the same work done at the timer would have: the longest one its credits " +
	"allow. A meeting that completes the block you were part-way through — or spans a block boundary " +
	"outright — is followed by the long break; one that lands mid-block is followed by the short one."

const readmeMeetingSkipClaim = "`skip` ends a meeting early and still credits the time actually spent in it, " +
	"which is what separates ending a meeting from skipping a pomodoro."

// readmeMeeting holds the README to the claims this file proves.
func readmeMeeting(t *testing.T) {
	t.Helper()
	raw, err := doctest.Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	readme := doctest.Unwrap(raw)
	for _, claim := range []string{readmeMeetingCreditClaim, readmeMeetingBlockClaim, readmeMeetingSkipClaim} {
		if !strings.Contains(readme, claim) {
			t.Fatalf("the README no longer says: %s", claim)
		}
	}
}

// The rounding rule, and the two examples the README works out for the reader,
// against the engine that actually decides them.
func TestReadmeStatesTheRoundingAMeetingsCreditUses(t *testing.T) {
	readmeMeeting(t)
	work := config.Default().Pomodoro.WorkMinutes
	if work != 25 {
		t.Fatalf("the README's examples assume a 25-minute pomodoro, but the default is %d", work)
	}

	if got := engine.MeetingCredits(60*time.Minute, work); got != 2 {
		t.Fatalf("a 60-minute meeting credits %d, but the README says 2", got)
	}
	if got := engine.MeetingCredits(10*time.Minute, work); got != 0 {
		t.Fatalf("a 10-minute meeting credits %d, but the README says none", got)
	}
	// "Rounded to the nearest, with half rounding up" is the rule those two
	// examples are drawn from, and neither of them lands on the half.
	for _, tc := range []struct {
		elapsed time.Duration
		want    int
	}{
		{12*time.Minute + 30*time.Second, 1},
		{12*time.Minute + 29*time.Second, 0},
		{37*time.Minute + 30*time.Second, 2},
		{37*time.Minute + 29*time.Second, 1},
	} {
		if got := engine.MeetingCredits(tc.elapsed, work); got != tc.want {
			t.Fatalf("%s credits %d, want %d -- half must round up", tc.elapsed, got, tc.want)
		}
	}
}

// The block claim: a break always follows, and which one is whatever the
// credits earned -- the long break when they complete or span the block, the
// short one when they land inside it.
func TestReadmeStatesWhatFollowsAMeetingAndItDoes(t *testing.T) {
	readmeMeeting(t)
	every := config.Default().Pomodoro.LongBreakEvery

	completing := lunchlessCore(t)
	completing.execute(cmdStart)
	for range every - 1 {
		completing.timer.CompletePeriod()
		completing.execute("confirm")
		completing.timer.CompletePeriod()
		completing.execute("confirm")
	}
	completing.execute("meeting 60")
	completing.timer.CompletePeriod()
	if next, _, _ := completing.nextStageLocked(); next != engine.LongBreak {
		t.Fatalf("a meeting completing the block leads to %s, but the README says the long break", next)
	}

	// Spanning the boundary outright, from a block with nothing in it.
	spanning := lunchlessCore(t)
	spanning.execute(fmt.Sprintf("meeting %d", (every+1)*config.Default().Pomodoro.WorkMinutes))
	spanning.timer.CompletePeriod()
	if next, _, _ := spanning.nextStageLocked(); next != engine.LongBreak {
		t.Fatalf("a meeting spanning the block leads to %s, but the README says the long break", next)
	}

	midBlock := lunchlessCore(t)
	midBlock.execute("meeting 30")
	midBlock.timer.CompletePeriod()
	if next, _, _ := midBlock.nextStageLocked(); next != engine.ShortBreak {
		t.Fatalf("a meeting mid-block leads to %s, but the README says the short break", next)
	}
}

// The skip claim: ending a meeting early credits the time spent, where
// skipping a pomodoro credits nothing.
func TestReadmeStatesEndingAMeetingEarlyStillCreditsItAndItDoes(t *testing.T) {
	readmeMeeting(t)

	meeting := lunchlessCore(t)
	meeting.execute("meeting 60")
	meeting.execute("skip")
	if meeting.timer.Snapshot().Engine.Skipped {
		t.Fatal("an ended meeting is marked skipped, so nothing about it would be credited")
	}

	pomodoro := lunchlessCore(t)
	pomodoro.execute(cmdStart)
	pomodoro.execute("skip")
	if !pomodoro.timer.Snapshot().Engine.Skipped {
		t.Fatal("a skipped pomodoro is not marked skipped, so the two are no longer separated")
	}
	if got := pomodoro.timer.Snapshot().Engine.CompletedToday; got != 0 {
		t.Fatalf("a skipped pomodoro credited %d, want 0", got)
	}
}
