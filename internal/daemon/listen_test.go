package daemon

import (
	"context"
	"errors"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
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
	defer first.Close()
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
	l.Close()
	if _, err := os.Stat(paths.Socket); !os.IsNotExist(err) {
		t.Fatal("expected socket removed on close")
	}
	if l2, err := Listen(paths); err != nil {
		t.Fatalf("expected relisten after close: %v", err)
	} else {
		l2.Close()
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
	resp.Body.Close()
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
	defer resp.Body.Close()

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
