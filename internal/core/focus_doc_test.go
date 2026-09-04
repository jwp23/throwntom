package core

import (
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/doctest"
)

// The README tells a reader when focus can be changed and when the daemon
// asks about it. Both are claims about the command handlers, so they are
// checked against the handlers here rather than left to whoever last edited
// the prose.

// readmeProse is the README with its wrapping undone, so a sentence can be
// looked for as it reads rather than as it is laid out.
func readmeProse(t *testing.T) string {
	t.Helper()
	readme, err := doctest.Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	return doctest.Unwrap(readme)
}

// TestReadmeSaysFocusIsNotTiedToARunningPomodoro pins the promise and the
// behaviour together: every focus verb answers in whatever state the timer is
// in, so a reader who focuses before starting is not refused.
func TestReadmeSaysFocusIsNotTiedToARunningPomodoro(t *testing.T) {
	want := "you can focus and unfocus in any timer state, including while idle"
	if prose := readmeProse(t); !strings.Contains(prose, want) {
		t.Errorf("README no longer says focus is available in any timer state (%q)", want)
	}

	c := newTestCoreWithTasks(t)
	c.execute(cmdTaskAddImportant)
	c.execute("task add second")
	// Two tasks focused, so the reorder verbs have somewhere to move to and a
	// refusal can only come from the timer state.
	for _, line := range []string{cmdTaskFocus1, "task focus 2", "task up 2", "task down 1", "task unfocus 1"} {
		if result := c.execute(line); result.err != nil {
			t.Errorf("%q was refused while idle: %v", line, result.err)
		}
	}
}

// TestReadmeSaysStartOffersBackTheFocusAlreadyChosen pins the seeding: the
// prompt start opens marks what is already focused, which is what makes
// choosing focus while idle worth doing.
func TestReadmeSaysStartOffersBackTheFocusAlreadyChosen(t *testing.T) {
	want := "Starting a pomodoro always asks which tasks it is for, offering back whatever is already focused"
	if prose := readmeProse(t); !strings.Contains(prose, want) {
		t.Errorf("README no longer says start offers back the focus already chosen (%q)", want)
	}

	c := newTestCoreWithTasks(t)
	c.execute(cmdTaskAddImportant)
	c.execute(cmdTaskFocus1)
	result := c.execute("start")
	if !strings.Contains(result.message, "*1) important work") {
		t.Fatalf("the prompt does not mark the task already focused: %q", result.message)
	}
}

// TestReadmeSaysConfirmAsksOnlyWhenNothingIsFocused pins the other half. The
// two verbs differ, and a reader told they behave alike would expect a break
// to end by asking again for focus they had already chosen.
func TestReadmeSaysConfirmAsksOnlyWhenNothingIsFocused(t *testing.T) {
	want := "confirming into a work phase asks only when nothing is focused yet"
	if prose := readmeProse(t); !strings.Contains(prose, want) {
		t.Errorf("README no longer says confirm asks only when nothing is focused (%q)", want)
	}

	for _, tc := range []struct {
		name       string
		focusFirst bool
		wantPrompt bool
	}{
		{"nothing focused", false, true},
		{"focus already chosen", true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestCoreWithTasks(t)
			c.execute(cmdTaskAddImportant)
			c.execute("start")
			c.execute("") // answer the prompt start opens, choosing nothing
			c.timer.CompletePeriod()
			c.execute("confirm") // -> short break
			if tc.focusFirst {
				c.execute(cmdTaskFocus1)
			}
			c.timer.CompletePeriod()
			c.execute("confirm") // -> work
			if got := c.FocusPromptPending(); got != tc.wantPrompt {
				t.Fatalf("confirm into work prompted = %v, want %v", got, tc.wantPrompt)
			}
		})
	}
}
