package core

import (
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/doctest"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

// The README's paragraph on lunch makes two claims about the daemon that no
// other test would catch going stale: that nothing in the timer's own flow
// ever leads to lunch, and that the verb is accepted whatever the timer is
// doing. Both are checked here against the daemon, so the sentence and the
// behaviour fail together.
const readmeLunchClaim = "`lunch` is the one break you choose rather than earn: no schedule starts it and " +
	"no finished pomodoro leads to it, so it is available from any state and never offered by the timer itself."

// readmeLunch returns the README with its wrapping removed, having first held
// it to the claim this file proves.
func readmeLunch(t *testing.T) string {
	t.Helper()
	raw, err := doctest.Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	readme := doctest.Unwrap(raw)
	if !strings.Contains(readme, readmeLunchClaim) {
		t.Fatalf("the README no longer says: %s", readmeLunchClaim)
	}
	return readme
}

// lunchlessCore is a Core with the morning reminder out of the way, so the
// stages under test are the cycle's own.
func lunchlessCore(t *testing.T) *Core {
	t.Helper()
	cfg := config.Default()
	cfg.MorningReminderPending = false
	return newCore(cfg, noopNotifier{})
}

// The stages the daemon publishes are what a client offers the user. Lunch is
// chosen rather than earned, so it must appear in neither, at any point of a
// whole block — including the boundary where the long break is earned, which
// is the one place a "deepest rest" might plausibly be substituted.
func TestReadmeSaysTheTimerNeverOffersLunch(t *testing.T) {
	readmeLunch(t)
	c := lunchlessCore(t)
	every := config.Default().Pomodoro.LongBreakEvery
	var stagesSeen stageTally

	stagesSeen.add(assertOffersNoLunch(t, c, "idle"))
	c.execute(cmdStart)
	for i := 1; i <= every; i++ {
		c.timer.CompletePeriod()
		stagesSeen.add(assertOffersNoLunch(t, c, "the pomodoro that just finished"))
		c.execute("confirm")
		stagesSeen.add(assertOffersNoLunch(t, c, "the break that just began"))
		c.timer.CompletePeriod()
		stagesSeen.add(assertOffersNoLunch(t, c, "the break that just finished"))
		c.execute("confirm")
	}
	c.execute("pause")
	stagesSeen.add(assertOffersNoLunch(t, c, "paused"))
	c.execute("resume")
	c.execute("stop")
	stagesSeen.add(assertOffersNoLunch(t, c, "stopped, with a phase owed"))
	c.execute("skip-today")
	stagesSeen.add(assertOffersNoLunch(t, c, "the day ended"))

	// A walk that published no stage at all would satisfy every assertion
	// above while checking nothing.
	if !stagesSeen.next || !stagesSeen.owed {
		t.Fatalf("the walk published next=%v owed=%v; it must reach both to prove anything",
			stagesSeen.next, stagesSeen.owed)
	}
}

// stageTally records which of the two published stages the walk ever saw.
type stageTally struct{ next, owed bool }

func (s *stageTally) add(next, owed bool) {
	s.next = s.next || next
	s.owed = s.owed || owed
}

// lunchStart is a state lunch has to be available from, and the way a user
// reaches it. `from` names the state the setup must actually land in, so a
// setup that stops short is caught rather than quietly testing idle eight
// times.
type lunchStart struct {
	name  string
	from  engine.State
	reach func(*Core)
}

// lunchStarts is every state the timer can be sitting in, built apart from the
// test that sweeps them: the setups carry loops of their own, and inlining
// them left the test reading as one long method rather than as the one claim
// it makes.
func lunchStarts(every int) []lunchStart {
	return []lunchStart{
		{"idle", engine.Idle, func(*Core) {}},
		{"a pomodoro", engine.Work, func(c *Core) { c.execute(cmdStart) }},
		{"a pomodoro waiting to be confirmed", engine.AwaitingConfirm, func(c *Core) {
			c.execute(cmdStart)
			c.timer.CompletePeriod()
		}},
		{"a short break", engine.ShortBreak, func(c *Core) {
			c.execute(cmdStart)
			c.timer.CompletePeriod()
			c.execute("confirm")
		}},
		{"a long break", engine.LongBreak, func(c *Core) {
			c.execute(cmdStart)
			for i := 1; i <= every; i++ {
				c.timer.CompletePeriod()
				c.execute("confirm")
				if i < every {
					c.timer.CompletePeriod()
					c.execute("confirm")
				}
			}
		}},
		{"paused", engine.Paused, func(c *Core) {
			c.execute(cmdStart)
			c.execute("pause")
		}},
		{"the day ended", engine.Idle, func(c *Core) { c.execute("skip-today") }},
		{"lunch itself", engine.Lunch, func(c *Core) { c.execute(cmdLunch) }},
	}
}

// The verb refuses nothing. Each state is reached the way a user reaches it,
// then lunch is taken from it.
func TestReadmeSaysLunchIsAvailableFromAnyState(t *testing.T) {
	readmeLunch(t)

	for _, tc := range lunchStarts(config.Default().Pomodoro.LongBreakEvery) {
		t.Run(tc.name, func(t *testing.T) {
			c := lunchlessCore(t)
			tc.reach(c)
			if got := c.timer.State(); got != tc.from {
				t.Fatalf("the setup for %s reached %s, not %s", tc.name, got, tc.from)
			}

			if result := c.execute(cmdLunch); result.err != nil {
				t.Fatalf("lunch from %s refused: %v", tc.name, result.err)
			}
			if got := c.timer.State(); got != engine.Lunch {
				t.Fatalf("lunch from %s left the timer %s", tc.name, got)
			}
		})
	}
}

// assertOffersNoLunch holds the two stages the daemon publishes — what confirm
// would move on to, and what start would enter — to naming anything but lunch,
// and reports which of them was published at all.
func assertOffersNoLunch(t *testing.T, c *Core, where string) (next, owed bool) {
	t.Helper()
	state := c.State()
	if state.NextStage != nil {
		if state.NextStage.State == engine.Lunch {
			t.Fatalf("the timer offered lunch as the next stage at %s", where)
		}
		next = true
	}
	if state.OwedStage != nil {
		if state.OwedStage.State == engine.Lunch {
			t.Fatalf("the timer offered lunch as the owed stage at %s", where)
		}
		owed = true
	}
	return next, owed
}
