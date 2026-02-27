package notifier

import "fmt"

type Notifier interface {
	PlaySound(name string) error
}

type runner func(name string, args ...string) error

type macOSNotifier struct {
	run runner
}

func NewMacOSNotifier() Notifier {
	return &macOSNotifier{run: runCommand}
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
