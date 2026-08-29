package notifier

import (
	"bytes"
	"errors"
	"strings"
	"testing"
)

const testSoundName = "default"

func TestNotifierFallbackOnCommandError(t *testing.T) {
	n := NewTestNotifier(func(name string, args ...string) error {
		return errors.New("exec failed")
	})
	if n.PlaySound(testSoundName) == nil {
		t.Fatal("expected contextual error")
	}
}

func TestLinuxNotifierWritesTerminalBell(t *testing.T) {
	var out bytes.Buffer
	n := &linuxTerminalNotifier{
		out: &out,
		run: func(name string, args ...string) error {
			return errors.New("no command available")
		},
	}

	if err := n.PlaySound(testSoundName); err != nil {
		t.Fatalf("play sound: %v", err)
	}
	if got := out.String(); got != "\a" {
		t.Fatalf("expected bell byte, got %q", got)
	}
}

func TestLinuxNotifierErrorsOnNilOutput(t *testing.T) {
	n := &linuxTerminalNotifier{
		run: func(name string, args ...string) error {
			return errors.New("no command available")
		},
	}
	if n.PlaySound(testSoundName) == nil {
		t.Fatal("expected nil output error")
	}
}

func TestLinuxNotifierUsesConfiguredCommandFirst(t *testing.T) {
	var gotName string
	var gotArgs []string
	n := &linuxTerminalNotifier{
		out:          &bytes.Buffer{},
		soundCommand: []string{"paplay", "/tmp/custom.oga"},
		run: func(name string, args ...string) error {
			gotName = name
			gotArgs = append([]string(nil), args...)
			return nil
		},
	}

	if err := n.PlaySound(testSoundName); err != nil {
		t.Fatalf("play sound: %v", err)
	}
	if gotName != "paplay" {
		t.Fatalf("expected custom command first, got %q", gotName)
	}
	if len(gotArgs) != 1 || gotArgs[0] != "/tmp/custom.oga" {
		t.Fatalf("unexpected custom args: %v", gotArgs)
	}
}

func TestNewCommandNotifierRejectsEmptyCommand(t *testing.T) {
	_, err := NewCommandNotifier(nil)
	if err == nil {
		t.Fatal("expected empty command error")
	}
}

func TestNewSystemNotifierByPlatform(t *testing.T) {
	tests := []struct {
		name      string
		goos      string
		wantError bool
	}{
		{name: "darwin", goos: "darwin"},
		{name: "linux", goos: "linux"},
		{name: "unsupported", goos: "windows", wantError: true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			n, err := NewSystemNotifier(tc.goos, &bytes.Buffer{}, nil)
			if tc.wantError {
				if err == nil {
					t.Fatal("expected unsupported platform error")
				}
				if !strings.Contains(err.Error(), "unsupported platform") {
					t.Fatalf("expected unsupported platform message, got %v", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("new system notifier: %v", err)
			}
			if n == nil {
				t.Fatal("expected notifier")
			}
		})
	}
}

func TestNewSystemNotifierUsesConfiguredCommandOnDarwin(t *testing.T) {
	n, err := NewSystemNotifier("darwin", &bytes.Buffer{}, []string{"echo", "ok"})
	if err != nil {
		t.Fatalf("new system notifier: %v", err)
	}
	if _, ok := n.(*commandNotifier); !ok {
		t.Fatalf("expected command sound player, got %T", n)
	}
}

func TestMacOSNotifierPlaysTheNamedSystemSound(t *testing.T) {
	tests := []struct {
		name string
		want string
	}{
		{name: "morning", want: "/System/Library/Sounds/Blow.aiff"},
		{name: "default", want: "/System/Library/Sounds/Glass.aiff"},
		{name: "test", want: "/System/Library/Sounds/Tink.aiff"},
		{name: "no-such-sound", want: "/System/Library/Sounds/Glass.aiff"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var gotArgs []string
			n := &macOSNotifier{run: func(name string, args ...string) error {
				gotArgs = append([]string{name}, args...)
				return nil
			}}
			if err := n.PlaySound(tc.name); err != nil {
				t.Fatalf("play sound: %v", err)
			}
			if len(gotArgs) != 2 || gotArgs[0] != "afplay" || gotArgs[1] != tc.want {
				t.Fatalf("expected afplay %s, got %v", tc.want, gotArgs)
			}
		})
	}
}

// The daemon has no user in front of it: under ADR-003 each client plays the
// reminder on its own platform, so the daemon's notifier must play nothing.
func TestSilentNotifierPlaysNothing(t *testing.T) {
	n := Silent()
	for _, name := range []string{"morning", "default", "test", "unknown"} {
		if err := n.PlaySound(name); err != nil {
			t.Fatalf("silent notifier reported %q as an error: %v", name, err)
		}
	}
}

func TestSilentNotifiersAreInterchangeable(t *testing.T) {
	if Silent() != Silent() {
		t.Fatal("expected every silent notifier to compare equal")
	}
}
