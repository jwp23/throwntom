package config

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

const testInterval = 2 * time.Millisecond

func writeConfig(t *testing.T, path, body string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}
}

// runWatcher starts w in the background and returns a func that stops it and
// waits for it to exit.
func runWatcher(t *testing.T, w Watcher) {
	t.Helper()
	// Read the baseline here, before the watcher exists, exactly as a caller
	// must: it is what makes an immediately following edit impossible to miss.
	baseline, _ := os.ReadFile(w.Path)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		w.Run(ctx, baseline)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
}

func TestWatcherReportsChangedConfig(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	writeConfig(t, path, "[pomodoro]\nwork_minutes = 25\n")

	changes := make(chan Config, 4)
	runWatcher(t, Watcher{
		Path:     path,
		Interval: testInterval,
		OnChange: func(cfg Config) { changes <- cfg },
	})

	writeConfig(t, path, "[pomodoro]\nwork_minutes = 40\n")

	select {
	case cfg := <-changes:
		if cfg.Pomodoro.WorkMinutes != 40 {
			t.Fatalf("expected work_minutes 40, got %d", cfg.Pomodoro.WorkMinutes)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("expected a change within 2s")
	}
}

func TestWatcherIgnoresUnchangedFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	writeConfig(t, path, "[pomodoro]\nwork_minutes = 25\n")

	changes := make(chan Config, 4)
	runWatcher(t, Watcher{
		Path:     path,
		Interval: testInterval,
		OnChange: func(cfg Config) { changes <- cfg },
	})

	// A rewrite with identical bytes is not a change, even though it moves
	// the file's modification time.
	time.Sleep(20 * testInterval)
	writeConfig(t, path, "[pomodoro]\nwork_minutes = 25\n")
	time.Sleep(20 * testInterval)

	if len(changes) != 0 {
		t.Fatalf("expected no change reports, got %d", len(changes))
	}
}

// Writing a file is not atomic: a poll can land between the truncate and the
// write. An empty config parses as every default, so applying one would
// replace the user's durations behind their back.
func TestWatcherIgnoresAHalfWrittenFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	writeConfig(t, path, "[pomodoro]\nwork_minutes = 40\n")

	w := Watcher{Path: path, Interval: testInterval}
	var applied []Config
	w.OnChange = func(cfg Config) { applied = append(applied, cfg) }

	// The truncated file is seen once and then replaced, exactly as an
	// editor's non-atomic write looks to a poller.
	state := watchState{applied: []byte("[pomodoro]\nwork_minutes = 40\n")}
	state.seen = state.applied
	writeConfig(t, path, "")
	state = w.poll(state)
	writeConfig(t, path, "[pomodoro]\nwork_minutes = 40\n")
	state = w.poll(state)
	state = w.poll(state)

	if len(applied) != 0 {
		t.Fatalf("expected nothing applied from a half-written file, got %+v", applied)
	}
}

func TestWatcherReportsAnUnreadableFileOnlyOnce(t *testing.T) {
	dir := t.TempDir()
	// A directory where the config should be is readable as a path but not
	// as a file, so every poll fails the same way.
	path := filepath.Join(dir, "config.toml")
	if err := os.Mkdir(path, 0o755); err != nil {
		t.Fatal(err)
	}

	var errs []error
	w := Watcher{Path: path, Interval: testInterval, OnError: func(err error) { errs = append(errs, err) }}
	state := watchState{}
	for i := 0; i < 5; i++ {
		state = w.poll(state)
	}

	if len(errs) != 1 {
		t.Fatalf("expected one report of a repeating error, got %d", len(errs))
	}
}

func TestWatcherReportsInvalidConfigWithoutApplying(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	writeConfig(t, path, "[pomodoro]\nwork_minutes = 25\n")

	changes := make(chan Config, 4)
	errs := make(chan error, 4)
	runWatcher(t, Watcher{
		Path:     path,
		Interval: testInterval,
		OnChange: func(cfg Config) { changes <- cfg },
		OnError:  func(err error) { errs <- err },
	})

	writeConfig(t, path, "[pomodoro]\nwork_minutes = -1\n")

	select {
	case err := <-errs:
		if err == nil {
			t.Fatal("expected a non-nil error")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("expected an error report within 2s")
	}
	if len(changes) != 0 {
		t.Fatal("expected no config to be applied from an invalid file")
	}
}

func TestWatcherPicksUpAFileCreatedLater(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")

	changes := make(chan Config, 4)
	runWatcher(t, Watcher{
		Path:     path,
		Interval: testInterval,
		OnChange: func(cfg Config) { changes <- cfg },
	})

	writeConfig(t, path, "[pomodoro]\nwork_minutes = 40\n")

	select {
	case cfg := <-changes:
		if cfg.Pomodoro.WorkMinutes != 40 {
			t.Fatalf("expected work_minutes 40, got %d", cfg.Pomodoro.WorkMinutes)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("expected a change within 2s")
	}
}

func TestWatcherStopsWithContext(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	writeConfig(t, path, "[pomodoro]\nwork_minutes = 25\n")

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		Watcher{Path: path, Interval: testInterval}.Run(ctx, nil)
	}()

	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("expected Run to return when the context ends")
	}
}
