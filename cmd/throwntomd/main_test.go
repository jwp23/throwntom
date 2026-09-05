package main

import (
	"fmt"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/daemon"
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

// Losing the single-instance lock is not a failure of this process: another
// throwntomd already owns the socket and is serving. Exiting non-zero there
// tells launchd the job crashed, and KeepAlive respawns it forever.
func TestExitCode(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want int
	}{
		{name: "served until shutdown", err: nil, want: 0},
		{name: "another instance owns the socket", err: daemon.ErrAlreadyRunning, want: 0},
		{name: "another instance, error wrapped", err: fmt.Errorf("listen: %w", daemon.ErrAlreadyRunning), want: 0},
		{name: "the socket could not be served", err: fmt.Errorf("permission denied"), want: 1},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := exitCode(tt.err); got != tt.want {
				t.Fatalf("exitCode(%v) = %d, want %d", tt.err, got, tt.want)
			}
		})
	}
}
