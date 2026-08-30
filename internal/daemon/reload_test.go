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
	"github.com/jwp23/throwntom/v3/internal/core"
)

// TestRunAppliesConfigChangesWithoutRestart is the boundary this feature
// exists for: an edit to config.toml reaches a running daemon's state.
func TestRunAppliesConfigChangesWithoutRestart(t *testing.T) {
	restore := configPollInterval
	configPollInterval = 5 * time.Millisecond
	t.Cleanup(func() { configPollInterval = restore })

	paths := tempPaths(t)
	paths.Config = filepath.Join(filepath.Dir(paths.Session), "config.toml")
	configBytes := []byte("[pomodoro]\nlong_break_every = 4\n")
	if err := os.WriteFile(paths.Config, configBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	cfg := config.Default()
	cfg.MorningReminderPending = false
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- Run(ctx, cfg, noopNotifier{}, paths, configBytes) }()
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
		if stateLongBreakEvery(t, client) == 3 {
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

// TestRunUsesTheGivenBaselineNotAFreshRead proves the fix for the race this
// guards against: an edit landing between the read that produced cfg and
// Run's watcher starting must still be picked up, not silently adopted as
// though it were already in force. Simulated here by handing Run a baseline
// that is stale relative to what is already on disk when Run starts.
func TestRunUsesTheGivenBaselineNotAFreshRead(t *testing.T) {
	restore := configPollInterval
	configPollInterval = 5 * time.Millisecond
	t.Cleanup(func() { configPollInterval = restore })

	paths := tempPaths(t)
	paths.Config = filepath.Join(filepath.Dir(paths.Session), "config.toml")
	staleBaseline := []byte("[pomodoro]\nlong_break_every = 4\n")
	// The file already holds the edit by the time Run starts; only the
	// baseline Run is given is stale, exactly as if the edit landed in the
	// gap between the read that produced cfg and this call.
	if err := os.WriteFile(paths.Config, []byte("[pomodoro]\nlong_break_every = 3\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg := config.Default()
	cfg.MorningReminderPending = false
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- Run(ctx, cfg, noopNotifier{}, paths, staleBaseline) }()
	defer func() {
		cancel()
		<-done
	}()

	client := unixClient(paths.Socket)
	waitForDaemon(t, client)

	deadline := time.Now().Add(5 * time.Second)
	for {
		if stateLongBreakEvery(t, client) == 3 {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("daemon never picked up the edit already on disk at startup; long_break_every is still %d", stateLongBreakEvery(t, client))
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// TestWatchConfigStopCancelsTheWatcher pins the invariant that lets
// watchConfig hand its cancel func to the caller instead of deferring it:
// the returned stop func must cancel the watcher context, so waiting on the
// watcher goroutine returns rather than blocking forever.
func TestWatchConfigStopCancelsTheWatcher(t *testing.T) {
	restore := configPollInterval
	configPollInterval = 5 * time.Millisecond
	t.Cleanup(func() { configPollInterval = restore })

	paths := tempPaths(t)
	paths.Config = filepath.Join(filepath.Dir(paths.Session), "config.toml")
	configBytes := []byte("[pomodoro]\nlong_break_every = 4\n")
	if err := os.WriteFile(paths.Config, configBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c, err := core.New(cfg, noopNotifier{}, paths)
	if err != nil {
		t.Fatal(err)
	}

	stop := watchConfig(context.Background(), paths.Config, configBytes, c)
	stopped := make(chan struct{})
	go func() {
		defer close(stopped)
		stop()
	}()
	select {
	case <-stopped:
	case <-time.After(5 * time.Second):
		t.Fatal("stop never returned; the watcher context was not cancelled")
	}
}
