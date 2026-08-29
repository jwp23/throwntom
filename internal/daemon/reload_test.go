package daemon

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
)

// TestRunAppliesConfigChangesWithoutRestart is the boundary this feature
// exists for: an edit to config.toml reaches a running daemon's state.
func TestRunAppliesConfigChangesWithoutRestart(t *testing.T) {
	restore := configPollInterval
	configPollInterval = 5 * time.Millisecond
	t.Cleanup(func() { configPollInterval = restore })

	paths := tempPaths(t)
	paths.Config = filepath.Join(filepath.Dir(paths.Session), "config.toml")
	if err := os.WriteFile(paths.Config, []byte("[pomodoro]\nlong_break_every = 4\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg := config.Default()
	cfg.MorningReminderPending = false
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- Run(ctx, cfg, noopNotifier{}, paths) }()
	defer func() {
		cancel()
		<-done
	}()

	client := unixClient(paths.Socket)
	waitForDaemon(t, client)

	if err := os.WriteFile(paths.Config, []byte("[pomodoro]\nlong_break_every = 3\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	deadline := time.Now().Add(5 * time.Second)
	for {
		if got := stateLongBreakEvery(t, client); got == 3 {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("daemon never applied the new config; long_break_every is still %d", stateLongBreakEvery(t, client))
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func waitForDaemon(t *testing.T, client *http.Client) {
	t.Helper()
	for i := 0; i < 100; i++ {
		resp, err := client.Get("http://throwntomd/v1/state")
		if err == nil {
			_ = resp.Body.Close()
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("daemon never came up")
}

func stateLongBreakEvery(t *testing.T, client *http.Client) int {
	t.Helper()
	resp, err := client.Get("http://throwntomd/v1/state")
	if err != nil {
		t.Fatalf("get state: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	var state struct {
		LongBreakEvery int `json:"long_break_every"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&state); err != nil {
		t.Fatalf("decode state: %v", err)
	}
	return state.LongBreakEvery
}
