package notifier

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

type Notifier interface {
	PlaySound(name string) error
	// ShowReminder posts a reminder the user can answer without the menu bar
	// app running. Platforms with nowhere to post one do nothing and report
	// no error.
	ShowReminder(title, body string) error
	// ClearReminder withdraws a reminder posted by ShowReminder.
	ClearReminder() error
}

// NoReminder is the do-nothing half of Notifier for platforms and tests that
// only care about sound.
type NoReminder struct{}

func (NoReminder) ShowReminder(title, body string) error { return nil }

func (NoReminder) ClearReminder() error { return nil }

// soundPlayer is the per-platform half of Notifier that makes noise.
type soundPlayer interface {
	PlaySound(name string) error
}

type runner func(name string, args ...string) error

type macOSNotifier struct {
	run runner
}

type commandNotifier struct {
	run     runner
	command []string
}

// darwinNotifier pairs any sound player with the bundled alert helper, so a
// user who overrides the sound still gets an actionable reminder.
type darwinNotifier struct {
	soundPlayer
	run   runner
	alert string
}

type linuxTerminalNotifier struct {
	NoReminder
	out          io.Writer
	run          runner
	soundCommand []string
}

func NewMacOSNotifier() Notifier {
	return newDarwinNotifier(runCommand, &macOSNotifier{run: runCommand})
}

func NewLinuxNotifier(out io.Writer, soundCommand []string) Notifier {
	return &linuxTerminalNotifier{out: out, run: runCommand, soundCommand: append([]string(nil), soundCommand...)}
}

func NewCommandNotifier(command []string) (Notifier, error) {
	if len(command) == 0 || strings.TrimSpace(command[0]) == "" {
		return nil, fmt.Errorf("sound_command requires at least a command name")
	}
	player := &commandNotifier{run: runCommand, command: append([]string(nil), command...)}
	return newDarwinNotifier(runCommand, player), nil
}

func NewSystemNotifier(goos string, out io.Writer, soundCommand []string) (Notifier, error) {
	switch goos {
	case "darwin":
		if len(soundCommand) > 0 {
			return NewCommandNotifier(soundCommand)
		}
		return NewMacOSNotifier(), nil
	case "linux":
		return NewLinuxNotifier(out, soundCommand), nil
	default:
		return nil, fmt.Errorf("unsupported platform %q", goos)
	}
}

func NewTestNotifier(run runner) Notifier {
	return newDarwinNotifier(run, &macOSNotifier{run: run})
}

func newDarwinNotifier(run runner, player soundPlayer) *darwinNotifier {
	return &darwinNotifier{soundPlayer: player, run: run, alert: findAlertHelper()}
}

// alertHelperName is the notification helper shipped beside throwntomd inside
// Throwntom.app. It is a separate executable because macOS only grants
// notification identity to code signed with the app's bundle identifier.
const alertHelperName = "throwntom-alert"

// findAlertHelper returns the helper's path, or "" when this build is not
// running out of the app bundle — a plain `go build` has no helper to call.
func findAlertHelper() string {
	exe, err := os.Executable()
	if err != nil {
		return ""
	}
	path := filepath.Join(filepath.Dir(exe), alertHelperName)
	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		return ""
	}
	return path
}

func (n *darwinNotifier) ShowReminder(title, body string) error {
	if n.alert == "" {
		return nil
	}
	if err := n.run(n.alert, "show", "--title", title, "--body", body); err != nil {
		return fmt.Errorf("show reminder %q: %w", title, err)
	}
	return nil
}

func (n *darwinNotifier) ClearReminder() error {
	if n.alert == "" {
		return nil
	}
	if err := n.run(n.alert, "clear"); err != nil {
		return fmt.Errorf("clear reminder: %w", err)
	}
	return nil
}

// systemSounds maps throwntom's sound names to macOS system sounds so the
// morning nudge, the confirm reminder and the sound test are told apart by ear.
var systemSounds = map[string]string{
	"morning": "Blow",
	"default": "Glass",
	"test":    "Tink",
}

const fallbackSystemSound = "Glass"

func systemSoundPath(name string) string {
	sound, ok := systemSounds[name]
	if !ok {
		sound = fallbackSystemSound
	}
	return "/System/Library/Sounds/" + sound + ".aiff"
}

func (n *macOSNotifier) PlaySound(name string) error {
	if err := n.run("afplay", systemSoundPath(name)); err != nil {
		return fmt.Errorf("play sound %q: %w", name, err)
	}
	return nil
}

func (n *commandNotifier) PlaySound(name string) error {
	if err := n.run(n.command[0], n.command[1:]...); err != nil {
		return fmt.Errorf("play sound %q via command %q: %w", name, strings.Join(n.command, " "), err)
	}
	return nil
}

func (n *linuxTerminalNotifier) PlaySound(name string) error {
	candidates := [][]string{}
	if len(n.soundCommand) > 0 {
		candidates = append(candidates, n.soundCommand)
	}
	candidates = append(candidates,
		[]string{"paplay", "/usr/share/sounds/freedesktop/stereo/bell.oga"},
		[]string{"canberra-gtk-play", "-i", "bell"},
		[]string{"aplay", "/usr/share/sounds/alsa/Front_Center.wav"},
	)

	failures := make([]string, 0, len(candidates)+1)
	for _, cmd := range candidates {
		if len(cmd) == 0 || strings.TrimSpace(cmd[0]) == "" {
			failures = append(failures, "invalid sound command")
			continue
		}
		if err := n.run(cmd[0], cmd[1:]...); err == nil {
			return nil
		} else {
			failures = append(failures, fmt.Sprintf("%s: %v", strings.Join(cmd, " "), err))
		}
	}

	if n.out == nil {
		failures = append(failures, "terminal output is nil")
		return fmt.Errorf("play sound %q: all sound playback methods failed: %s", name, strings.Join(failures, "; "))
	}
	if _, err := n.out.Write([]byte("\a")); err == nil {
		return nil
	} else {
		failures = append(failures, fmt.Sprintf("terminal bell: %v", err))
		return fmt.Errorf("play sound %q: all sound playback methods failed: %s", name, strings.Join(failures, "; "))
	}
}
