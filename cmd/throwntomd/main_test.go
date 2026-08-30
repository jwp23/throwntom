package main

import (
	"testing"

	"github.com/jwp23/throwntom/v3/internal/notifier"
)

// ADR-003: the daemon owns timing and state, each client owns presentation on
// its own platform. A sound is presentation, and nothing is in front of the
// daemon to hear it, so the daemon plays none.
func TestDaemonPlaysNoSound(t *testing.T) {
	if daemonNotifier() != notifier.Silent() {
		t.Fatal("expected the daemon to run with a silent notifier")
	}
}
