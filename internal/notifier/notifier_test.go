package notifier

import (
	"bytes"
	"errors"
	"reflect"
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
	darwin, ok := n.(*darwinNotifier)
	if !ok {
		t.Fatalf("expected darwin notifier, got %T", n)
	}
	if _, ok := darwin.soundPlayer.(*commandNotifier); !ok {
		t.Fatalf("expected command sound player, got %T", darwin.soundPlayer)
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

func TestDarwinNotifierRunsTheAlertHelper(t *testing.T) {
	var calls [][]string
	n := &darwinNotifier{
		soundPlayer: &macOSNotifier{run: func(string, ...string) error { return nil }},
		alert:       "/Apps/Throwntom.app/Contents/MacOS/throwntom-alert",
		run: func(name string, args ...string) error {
			calls = append(calls, append([]string{name}, args...))
			return nil
		},
	}

	if err := n.ShowReminder("Throwntom", "Ready to start a pomodoro"); err != nil {
		t.Fatalf("show reminder: %v", err)
	}
	if err := n.ClearReminder(); err != nil {
		t.Fatalf("clear reminder: %v", err)
	}

	want := [][]string{
		{"/Apps/Throwntom.app/Contents/MacOS/throwntom-alert", "show", "--title", "Throwntom", "--body", "Ready to start a pomodoro"},
		{"/Apps/Throwntom.app/Contents/MacOS/throwntom-alert", "clear"},
	}
	if !reflect.DeepEqual(calls, want) {
		t.Fatalf("expected %v, got %v", want, calls)
	}
}

func TestDarwinNotifierWithoutAHelperIsSilentlyInert(t *testing.T) {
	n := &darwinNotifier{
		soundPlayer: &macOSNotifier{run: func(string, ...string) error { return nil }},
		run: func(name string, args ...string) error {
			t.Fatalf("unexpected helper call: %s %v", name, args)
			return nil
		},
	}

	if err := n.ShowReminder("Throwntom", "Ready"); err != nil {
		t.Fatalf("show reminder: %v", err)
	}
	if err := n.ClearReminder(); err != nil {
		t.Fatalf("clear reminder: %v", err)
	}
}

func TestDarwinNotifierReportsHelperFailure(t *testing.T) {
	n := &darwinNotifier{
		soundPlayer: &macOSNotifier{run: func(string, ...string) error { return nil }},
		alert:       "/Apps/Throwntom.app/Contents/MacOS/throwntom-alert",
		run:         func(string, ...string) error { return errors.New("helper missing") },
	}

	if err := n.ShowReminder("Throwntom", "Ready"); err == nil {
		t.Fatal("expected show reminder error")
	}
	if err := n.ClearReminder(); err == nil {
		t.Fatal("expected clear reminder error")
	}
}

func TestLinuxNotifierHasNoActionableReminder(t *testing.T) {
	n := NewLinuxNotifier(&bytes.Buffer{}, nil)
	if err := n.ShowReminder("Throwntom", "Ready"); err != nil {
		t.Fatalf("show reminder: %v", err)
	}
	if err := n.ClearReminder(); err != nil {
		t.Fatalf("clear reminder: %v", err)
	}
}
