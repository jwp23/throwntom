package notifier

import (
	"errors"
	"testing"
)

func TestNotifierFallbackOnCommandError(t *testing.T) {
	n := NewTestNotifier(func(name string, args ...string) error {
		return errors.New("exec failed")
	})
	if err := n.PlaySound("default"); err == nil {
		t.Fatal("expected contextual error")
	}
}
