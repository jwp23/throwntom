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

// sound_command is where the docs have gone wrong most often, and the claims
// are all about what gets run: which element is the executable, whether the
// sound's name reaches the command, and what happens when it fails. Each of
// those is checked here against the sentence that makes it.

// soundNames is every name the rest of the program asks for. The docs claim
// none of them reaches a configured command.
var soundNames = []string{"morning", "default", "test", "unrecognised"}

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
	mustContain(t, "README.md", doctest.ReadUnwrapped(t, "README.md"),
		"the first item is the executable, the rest are its arguments")
	mustContain(t, "the config template", doctest.UnwrapComments(config.Template),
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
	mustContain(t, "README.md", doctest.ReadUnwrapped(t, "README.md"), "it *replaces* the built-in sound entirely")
	mustContain(t, "the config template", doctest.UnwrapComments(config.Template),
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

// linuxChainSpan captures the README's ordered list of what Linux falls back
// to as a single span, rather than fixing how many fallbacks there are: a
// regex with one capture group per fallback stops matching at all the moment
// a correctly documented fallback is added, misreporting a live chain as an
// absent one.
var linuxChainSpan = regexp.MustCompile(
	"it is tried first and, if it fails, throwntom falls back to (.+?), then the terminal bell")

// backtickedName matches one command name inside a backtick-delimited list.
var backtickedName = regexp.MustCompile("`([^`]+)`")

// documentedLinuxFallbacks reads the README's Linux fallback chain, in order,
// however many commands it names.
func documentedLinuxFallbacks(t *testing.T, prose string) []string {
	t.Helper()
	m := linuxChainSpan.FindStringSubmatch(prose)
	if m == nil {
		t.Fatal("README no longer states the Linux sound fallback order")
	}
	var names []string
	for _, n := range backtickedName.FindAllStringSubmatch(m[1], -1) {
		names = append(names, n[1])
	}
	return names
}

// TestDocumentedLinuxFallbacksReadsAnyLength pins documentedLinuxFallbacks to
// arbitrary length: the old regex hardcoded three capture groups and would
// have failed to match this fixture's fourth fallback outright, misreporting
// a correctly updated README as one that "no longer states" the chain.
func TestDocumentedLinuxFallbacksReadsAnyLength(t *testing.T) {
	prose := "it is tried first and, if it fails, throwntom falls back to " +
		"`paplay`, `canberra-gtk-play`, `aplay`, `speaker-test`, then the terminal bell"
	got := documentedLinuxFallbacks(t, prose)
	want := []string{"paplay", "canberra-gtk-play", "aplay", "speaker-test"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("documentedLinuxFallbacks(%q) = %v, want %v", prose, got, want)
	}
}

// TestLinuxFallsBackThroughTheDocumentedChain pins the README's fallback
// order to the order the notifier actually tries, the configured command
// included — the difference from macOS the docs draw twice.
func TestLinuxFallsBackThroughTheDocumentedChain(t *testing.T) {
	m := documentedLinuxFallbacks(t, doctest.ReadUnwrapped(t, "README.md"))
	mustContain(t, "the config template", doctest.UnwrapComments(config.Template),
		"On Linux that same chain also backs up a command that fails")

	var calls [][]string
	out := &bytes.Buffer{}
	// Built the way the terminal interface builds it, so the claim covers the
	// wiring too: a constructor that dropped soundCommand would leave the
	// README's "it is tried first" false with the chain itself intact.
	built, err := NewSystemNotifier("linux", out, []string{"mycommand"})
	if err != nil {
		t.Fatalf("build notifier: %v", err)
	}
	n, ok := built.(*linuxTerminalNotifier)
	if !ok {
		t.Fatalf("a configured sound_command on Linux built a %T, not the terminal notifier", built)
	}
	n.run = recordRun(&calls, errors.New("command failed"))
	if err := n.PlaySound("default"); err != nil {
		t.Fatalf("play sound: %v", err)
	}

	want := append([]string{"mycommand"}, m...)
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

// TestLinuxStopsAtAConfiguredCommandThatWorks is the other half of "it is
// tried first": a command that succeeds ends the chain. Without this the
// README would read true even if the fallbacks ran alongside it.
func TestLinuxStopsAtAConfiguredCommandThatWorks(t *testing.T) {
	var calls [][]string
	out := &bytes.Buffer{}
	built, err := NewSystemNotifier("linux", out, []string{"mycommand"})
	if err != nil {
		t.Fatalf("build notifier: %v", err)
	}
	n, ok := built.(*linuxTerminalNotifier)
	if !ok {
		t.Fatalf("a configured sound_command on Linux built a %T, not the terminal notifier", built)
	}
	n.run = recordRun(&calls, nil)
	if err := n.PlaySound("default"); err != nil {
		t.Fatalf("play sound: %v", err)
	}

	if len(calls) != 1 || calls[0][0] != "mycommand" {
		t.Fatalf("Linux ran %v, want only the configured command that succeeded", calls)
	}
	if out.String() != "" {
		t.Fatalf("the terminal bell rang after the command succeeded: %q", out.String())
	}
}

// builtInSoundsSpan captures the README's parenthetical naming every built-in
// macOS sound as a single span, rather than fixing how many sounds there are:
// a regex with one capture group per sound stops matching at all the moment a
// correctly documented sound is added, misreporting a live list as an absent
// one.
var builtInSoundsSpan = regexp.MustCompile(`the built-in choice is (.+?)\)`)

// roleToSoundName maps the README's English description of each sound's role
// to the name the rest of the program asks for it by.
var roleToSoundName = map[string]string{
	"the morning nudge": "morning",
	"confirm reminders": "default",
	"`test-sound`":      "test",
}

// documentedBuiltInSoundRoles splits the README's built-in sound span into
// its "<Name> for <role>" segments, however many there are.
func documentedBuiltInSoundRoles(t *testing.T, span string) map[string]string {
	t.Helper()
	roles := map[string]string{}
	for _, segment := range strings.Split(span, ", ") {
		name, role, found := strings.Cut(segment, " for ")
		if !found {
			t.Fatalf("README's built-in sound list has a segment %q not shaped %q", segment, "<Name> for <role>")
		}
		roles[role] = name
	}
	return roles
}

// TestDocumentedBuiltInSoundRolesReadsAnyLength pins documentedBuiltInSoundRoles
// to arbitrary length. The old regex hardcoded three capture groups with no
// anchor at the end, so a fourth sound appended to the list was silently
// dropped from what the test read rather than reported as drift — the failure
// mode this test proves does not recur here.
func TestDocumentedBuiltInSoundRolesReadsAnyLength(t *testing.T) {
	span := "Blow for the morning nudge, Glass for confirm reminders, Tink for `test-sound`, Sosumi for `break-sound`"
	got := documentedBuiltInSoundRoles(t, span)
	want := map[string]string{
		"the morning nudge": "Blow",
		"confirm reminders": "Glass",
		"`test-sound`":      "Tink",
		"`break-sound`":     "Sosumi",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("documentedBuiltInSoundRoles(%q) = %v, want %v", span, got, want)
	}
}

// TestBuiltInMacOSSoundsAreTheOnesDocumented pins the names the README gives
// a reader picking a different system sound.
func TestBuiltInMacOSSoundsAreTheOnesDocumented(t *testing.T) {
	readme := doctest.ReadUnwrapped(t, "README.md")
	m := builtInSoundsSpan.FindStringSubmatch(readme)
	if m == nil {
		t.Fatal("README no longer names the built-in macOS sounds")
	}
	roles := documentedBuiltInSoundRoles(t, m[1])
	documented := map[string]string{}
	for role, name := range roles {
		key, ok := roleToSoundName[role]
		if !ok {
			t.Fatalf("README names a built-in sound for %q, which this test does not recognise as a sound role", role)
		}
		documented[key] = name
	}
	if len(documented) != len(roleToSoundName) {
		t.Fatalf("README documents %v, want one sound for each of %v", documented, roleToSoundName)
	}
	mustContain(t, "README.md", readme,
		"a system sound chosen by name (`morning`→"+documented["morning"]+
			", `default`→"+documented["default"]+", `test`→"+documented["test"]+")")

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

// The claim every sound_command paragraph rests on — throwntomd plays no
// sound at all (ADR-007) — is pinned in cmd/throwntomd/main_test.go, next to
// TestDaemonPlaysNoSound, which is where the daemon's notifier is actually
// built. Checking it here as well would only restate that silentNotifier's
// PlaySound returns nil and that Audible type-asserts it, both already
// covered by TestAudibleDistinguishesTheSilentNotifier in notifier_test.go.
