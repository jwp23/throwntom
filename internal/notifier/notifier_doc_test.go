package notifier

import (
	"bytes"
	"errors"
	"reflect"
	"regexp"
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/doctest"
)

// templateText is the config template's prose, which documents sound_command
// alongside the README and must agree with it.
func templateText(t *testing.T) string {
	t.Helper()
	return config.Template
}

// sound_command is where the docs have gone wrong most often, and the claims
// are all about what gets run: which element is the executable, whether the
// sound's name reaches the command, and what happens when it fails. Each of
// those is checked here against the sentence that makes it.

// soundNames is every name the rest of the program asks for. The docs claim
// none of them reaches a configured command.
var soundNames = []string{"morning", "default", "test", "unrecognised"}

func readmeText(t *testing.T) string {
	t.Helper()
	readme, err := doctest.Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	return doctest.Unwrap(readme)
}

func mustContain(t *testing.T, source, text, want string) {
	t.Helper()
	if !strings.Contains(text, want) {
		t.Errorf("%s no longer says %q", source, want)
	}
}

// recordRun captures what a notifier ran, so a claim about the command line
// is checked against the command line and not against an error message.
func recordRun(calls *[][]string, err error) runner {
	return func(name string, args ...string) error {
		*calls = append(*calls, append([]string{name}, args...))
		return err
	}
}

// TestConfiguredCommandRunsAsWrittenWithoutTheSoundName pins the template's
// "It is run as written; the sound name is not passed to it" and the README's
// "the first item is the executable, the rest are its arguments".
func TestConfiguredCommandRunsAsWrittenWithoutTheSoundName(t *testing.T) {
	mustContain(t, "README.md", readmeText(t),
		"the first item is the executable, the rest are its arguments")
	mustContain(t, "the config template", doctest.Unwrap(templateText(t)),
		"It is run as written; the sound name is not passed to it")

	command := []string{"afplay", "-v", "2", "/System/Library/Sounds/Purr.aiff"}
	for _, name := range soundNames {
		var calls [][]string
		n := &commandNotifier{run: recordRun(&calls, nil), command: command}
		if err := n.PlaySound(name); err != nil {
			t.Fatalf("play %q: %v", name, err)
		}
		if len(calls) != 1 {
			t.Fatalf("play %q ran %d commands, want exactly the configured one", name, len(calls))
		}
		if !reflect.DeepEqual(calls[0], command) {
			t.Fatalf("play %q ran %v, want the command as written %v", name, calls[0], command)
		}
	}
}

// TestMacOSReplacesTheBuiltInSoundOutright pins the README's "On macOS, it
// replaces the built-in sound entirely" and the template's "on macOS it
// replaces the sound outright": there is no fallback, so a failing command
// makes no noise and says so.
func TestMacOSReplacesTheBuiltInSoundOutright(t *testing.T) {
	mustContain(t, "README.md", readmeText(t), "it *replaces* the built-in sound entirely")
	mustContain(t, "the config template", doctest.Unwrap(templateText(t)),
		"on macOS it replaces the sound outright")

	var calls [][]string
	n, err := NewSystemNotifier("darwin", &bytes.Buffer{}, []string{"mycommand"})
	if err != nil {
		t.Fatalf("build notifier: %v", err)
	}
	cmd, ok := n.(*commandNotifier)
	if !ok {
		t.Fatalf("a configured sound_command on macOS built a %T, not the command notifier", n)
	}
	cmd.run = recordRun(&calls, errors.New("command failed"))

	if err := cmd.PlaySound("default"); err == nil {
		t.Fatal("a failing command reported success; macOS has no fallback to hide it")
	}
	if len(calls) != 1 || calls[0][0] != "mycommand" {
		t.Fatalf("macOS tried %v, want only the configured command", calls)
	}
}

// linuxChain matches the README's ordered list of what Linux falls back to.
var linuxChain = regexp.MustCompile(
	"it is tried first and, if it fails, throwntom falls back to `([^`]+)`, `([^`]+)`, `([^`]+)`, then the terminal bell")

// TestLinuxFallsBackThroughTheDocumentedChain pins the README's fallback
// order to the order the notifier actually tries, the configured command
// included — the difference from macOS the docs draw twice.
func TestLinuxFallsBackThroughTheDocumentedChain(t *testing.T) {
	m := linuxChain.FindStringSubmatch(readmeText(t))
	if m == nil {
		t.Fatal("README no longer states the Linux sound fallback order")
	}
	mustContain(t, "the config template", doctest.Unwrap(templateText(t)),
		"On Linux that same chain also backs up a command that fails")

	var calls [][]string
	out := &bytes.Buffer{}
	n := &linuxTerminalNotifier{
		out:          out,
		soundCommand: []string{"mycommand"},
		run:          recordRun(&calls, errors.New("command failed")),
	}
	if err := n.PlaySound("default"); err != nil {
		t.Fatalf("play sound: %v", err)
	}

	want := append([]string{"mycommand"}, m[1:]...)
	var tried []string
	for _, call := range calls {
		tried = append(tried, call[0])
	}
	if !reflect.DeepEqual(tried, want) {
		t.Fatalf("Linux tried %v, README documents %v", tried, want)
	}
	if out.String() != "\a" {
		t.Fatalf("the chain ended with %q, README documents the terminal bell", out.String())
	}
}

// builtInSounds matches the README's parenthetical naming each built-in macOS
// sound, in both the Config section and the Notes.
var builtInSounds = regexp.MustCompile(
	`the built-in choice is (\w+) for the morning nudge, (\w+) for confirm reminders, (\w+) for ` + "`test-sound`")

// TestBuiltInMacOSSoundsAreTheOnesDocumented pins the names the README gives
// a reader picking a different system sound.
func TestBuiltInMacOSSoundsAreTheOnesDocumented(t *testing.T) {
	m := builtInSounds.FindStringSubmatch(readmeText(t))
	if m == nil {
		t.Fatal("README no longer names the built-in macOS sounds")
	}
	documented := map[string]string{"morning": m[1], "default": m[2], "test": m[3]}
	mustContain(t, "README.md", readmeText(t),
		"a system sound chosen by name (`morning`→"+m[1]+", `default`→"+m[2]+", `test`→"+m[3]+")")

	for name, sound := range documented {
		var calls [][]string
		n := &macOSNotifier{run: recordRun(&calls, nil)}
		if err := n.PlaySound(name); err != nil {
			t.Fatalf("play %q: %v", name, err)
		}
		want := []string{"afplay", "/System/Library/Sounds/" + sound + ".aiff"}
		if len(calls) != 1 || !reflect.DeepEqual(calls[0], want) {
			t.Fatalf("play %q ran %v, README documents %v", name, calls, want)
		}
	}
}

// TestTheDaemonsNotifierPlaysNothing pins the claim every sound_command
// paragraph rests on: throwntomd plays no sound at all (ADR-007), which is
// why the setting belongs to the terminal UI alone.
func TestTheDaemonsNotifierPlaysNothing(t *testing.T) {
	mustContain(t, "README.md", readmeText(t), "`throwntomd` plays no sound at all")

	var calls [][]string
	silent := Silent()
	if err := silent.PlaySound("default"); err != nil {
		t.Fatalf("the silent notifier reported an error: %v", err)
	}
	if len(calls) != 0 {
		t.Fatalf("the silent notifier ran %v", calls)
	}
	if Audible(silent) {
		t.Fatal("the daemon's notifier reports itself audible")
	}
}
