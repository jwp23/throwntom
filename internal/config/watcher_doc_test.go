package config

import (
	"fmt"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/doctest"
)

// The README tells a reader how long an edit takes to land and why: a poll
// period, and a rule that the same bytes must be seen twice. Both are numbers
// a reader plans around, so both are checked against the watcher here.

func readmeProse(t *testing.T) string {
	t.Helper()
	readme, err := doctest.Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	return doctest.Unwrap(readme)
}

// pollPeriod matches the README's stated poll period, spelled out in words.
var pollPeriod = regexp.MustCompile(`It polls every (\w+) seconds`)

var numberWords = map[string]time.Duration{
	"one": time.Second, "two": 2 * time.Second, "three": 3 * time.Second,
	"four": 4 * time.Second, "five": 5 * time.Second, "ten": 10 * time.Second,
}

// TestDocumentedPollPeriodIsTheWatchersOwn pins the README's "It polls every
// two seconds" to DefaultWatchInterval, which is what the daemon runs with.
func TestDocumentedPollPeriodIsTheWatchersOwn(t *testing.T) {
	m := pollPeriod.FindStringSubmatch(readmeProse(t))
	if m == nil {
		t.Fatal("README no longer states how often throwntomd polls config.toml")
	}
	want, ok := numberWords[m[1]]
	if !ok {
		t.Fatalf("README states a poll period of %q seconds, which this test cannot read as a number", m[1])
	}
	if DefaultWatchInterval != want {
		t.Fatalf("README documents a %s poll period, the watcher uses %s", want, DefaultWatchInterval)
	}
}

// TestASaveLandsOnTheSecondPollThatSeesIt pins the README's "waits for an
// edit to stop changing before applying it, so a save lands on the second
// poll that sees it" — the reason an edit takes a little longer than one poll.
func TestASaveLandsOnTheSecondPollThatSeesIt(t *testing.T) {
	prose := readmeProse(t)
	for _, want := range []string{
		"waits for an edit to stop changing before applying it",
		"a save lands on the second poll that sees it",
	} {
		if !strings.Contains(prose, want) {
			t.Errorf("README no longer says %q", want)
		}
	}

	path := configWithWorkMinutes(t, 25)
	var applied []int
	w := Watcher{Path: path, OnChange: func(cfg Config) {
		applied = append(applied, cfg.Pomodoro.WorkMinutes)
	}}

	state := w.poll(watchState{})
	if len(applied) != 0 {
		t.Fatalf("the first poll to see the file applied %v", applied)
	}
	w.poll(state)
	if len(applied) != 1 || applied[0] != 25 {
		t.Fatalf("the second poll applied %v, want the file's 25", applied)
	}
}

// TestEmptyingTheConfigResetsNothing pins the template's "An empty file is
// read as a save still in flight and ignored, so emptying this one resets
// nothing" — the case where applying the file would silently replace the
// user's durations with defaults.
func TestEmptyingTheConfigResetsNothing(t *testing.T) {
	if !strings.Contains(doctest.Unwrap(Template),
		"An empty file is read as a save still in flight and ignored, so emptying this one resets nothing") {
		t.Error("the config template no longer says an empty file is ignored")
	}

	path := configWithWorkMinutes(t, 50)
	var applied []int
	w := Watcher{Path: path, OnChange: func(cfg Config) {
		applied = append(applied, cfg.Pomodoro.WorkMinutes)
	}}

	state := w.poll(w.poll(watchState{}))
	if len(applied) != 1 {
		t.Fatalf("setup: expected the file applied once, got %v", applied)
	}

	writeConfig(t, path, "")
	w.poll(w.poll(state))
	if len(applied) != 1 {
		t.Fatalf("emptying the config applied %v, resetting the user's durations to defaults", applied)
	}
}

// configWithWorkMinutes writes a config file stating one work_minutes value,
// so an apply is told apart from a non-apply by the value that arrived.
func configWithWorkMinutes(t *testing.T, minutes int) string {
	t.Helper()
	path := t.TempDir() + "/config.toml"
	writeConfig(t, path, fmt.Sprintf("[pomodoro]\nwork_minutes = %d\n", minutes))
	return path
}
