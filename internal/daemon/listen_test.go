package daemon

import (
	"bytes"
	"context"
	"errors"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/app"
	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/session"
)

// shortTempDir returns a temp directory rooted directly under /tmp rather
// than t.TempDir()'s (often long, per-test) path, since AF_UNIX socket paths
// are limited to ~104 bytes on macOS and t.TempDir() paths can exceed that.
func shortTempDir(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "throwntomd-test")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })
	return dir
}

func tempPaths(t *testing.T) core.Paths {
	t.Helper()
	dir := shortTempDir(t)
	return core.Paths{
		Tasks:   filepath.Join(dir, "tasks.json"),
		Session: filepath.Join(dir, "session.json"),
		Events:  filepath.Join(dir, "events.jsonl"),
		Socket:  filepath.Join(dir, "d.sock"),
		Lock:    filepath.Join(dir, "d.lock"),
	}
}

func TestListenRejectsSecondInstance(t *testing.T) {
	paths := tempPaths(t)
	first, err := Listen(paths)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = first.Close() }()
	if _, err := Listen(paths); !errors.Is(err, ErrAlreadyRunning) {
		t.Fatalf("expected ErrAlreadyRunning, got %v", err)
	}
}

func TestListenReplacesStaleSocket(t *testing.T) {
	paths := tempPaths(t)
	if err := os.WriteFile(paths.Socket, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	l, err := Listen(paths)
	if err != nil {
		t.Fatalf("expected stale socket to be replaced: %v", err)
	}
	_ = l.Close()
	if _, err := os.Stat(paths.Socket); !os.IsNotExist(err) {
		t.Fatal("expected socket removed on close")
	}
	if l2, err := Listen(paths); err != nil {
		t.Fatalf("expected relisten after close: %v", err)
	} else {
		_ = l2.Close()
	}
}

func unixClient(socket string) *http.Client {
	return &http.Client{Transport: &http.Transport{
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "unix", socket)
		},
	}}
}

func TestRunServesUntilCancelledAndSavesSession(t *testing.T) {
	paths := tempPaths(t)
	cfg := config.Default()
	cfg.MorningReminderPending = false
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- Run(ctx, cfg, noopNotifier{}, paths) }()

	client := unixClient(paths.Socket)
	var resp *http.Response
	var err error
	for i := 0; i < 50; i++ {
		resp, err = client.Get("http://throwntomd/v1/state")
		if err == nil {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if err != nil {
		t.Fatalf("daemon never came up: %v", err)
	}
	_ = resp.Body.Close()
	postJSONWith(t, client, "http://throwntomd/v1/timer/new-cycle", nil)

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not return after cancel")
	}
	if _, err := os.Stat(paths.Session); err != nil {
		t.Fatalf("expected session saved on shutdown: %v", err)
	}
}

func TestRunReturnsPromptlyWithOpenSSEClient(t *testing.T) {
	paths := tempPaths(t)
	cfg := config.Default()
	cfg.MorningReminderPending = false
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- Run(ctx, cfg, noopNotifier{}, paths) }()

	client := unixClient(paths.Socket)
	var resp *http.Response
	var err error
	for i := 0; i < 50; i++ {
		resp, err = client.Get("http://throwntomd/v1/events")
		if err == nil {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if err != nil {
		t.Fatalf("daemon never came up: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not return within 5s with an open SSE client")
	}
}

type recordingNotifier struct {
	mu     sync.Mutex
	sounds int
}

func (r *recordingNotifier) PlaySound(string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.sounds++
	return nil
}

func (r *recordingNotifier) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.sounds
}

// seedExpiredWorkSession writes a session from earlier today whose work phase
// has already ended: loading it completes the period, starts the confirm
// reminder and rewrites the file.
func seedExpiredWorkSession(t *testing.T, path string) {
	t.Helper()
	now := time.Now()
	data := session.Data{
		SavedAt: now.Add(-time.Minute),
		App: app.Snapshot{
			Engine: engine.Snapshot{
				State:          engine.Work,
				LastPhase:      engine.Work,
				WorkDayStarted: true,
				WorkDate:       now,
			},
			PhaseEndAt: now.Add(-time.Second),
		},
	}
	if err := session.Save(path, data); err != nil {
		t.Fatal(err)
	}
}

func TestRunLeavesSessionUntouchedWhenAlreadyRunning(t *testing.T) {
	paths := tempPaths(t)
	held, err := Listen(paths)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = held.Close() }()

	seedExpiredWorkSession(t, paths.Session)
	before, err := os.ReadFile(paths.Session)
	if err != nil {
		t.Fatal(err)
	}

	n := &recordingNotifier{}
	if err := Run(context.Background(), config.Default(), n, paths); !errors.Is(err, ErrAlreadyRunning) {
		t.Fatalf("expected ErrAlreadyRunning, got %v", err)
	}
	// A core built before the lock check saves and notifies from background
	// goroutines; give those a chance to be observed.
	time.Sleep(100 * time.Millisecond)

	after, err := os.ReadFile(paths.Session)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("losing instance rewrote the session file")
	}
	if n.count() != 0 {
		t.Fatalf("losing instance played %d sounds", n.count())
	}
}
