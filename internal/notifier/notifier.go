package notifier

import (
	"fmt"
	"io"
	"strings"
)

type Notifier interface {
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

type linuxTerminalNotifier struct {
	out          io.Writer
	run          runner
	soundCommand []string
}

func NewMacOSNotifier() Notifier {
	return &macOSNotifier{run: runCommand}
}

func NewLinuxNotifier(out io.Writer, soundCommand []string) Notifier {
	return &linuxTerminalNotifier{out: out, run: runCommand, soundCommand: append([]string(nil), soundCommand...)}
}

func NewCommandNotifier(command []string) (Notifier, error) {
	if len(command) == 0 || strings.TrimSpace(command[0]) == "" {
		return nil, fmt.Errorf("sound_command requires at least a command name")
	}
	return &commandNotifier{run: runCommand, command: append([]string(nil), command...)}, nil
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
	return &macOSNotifier{run: run}
}

func (n *macOSNotifier) PlaySound(name string) error {
	soundPath := "/System/Library/Sounds/Glass.aiff"
	if err := n.run("afplay", soundPath); err != nil {
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
