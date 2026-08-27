package main

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/daemon"
)

type noopNotifier struct{}

func (noopNotifier) PlaySound(string) error { return nil }

func newServer(t *testing.T) (*httptest.Server, *core.Core) {
	t.Helper()
	dir := t.TempDir()
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c, err := core.New(cfg, noopNotifier{}, core.Paths{
		Tasks: filepath.Join(dir, "tasks.json"), Session: filepath.Join(dir, "session.json"), Events: filepath.Join(dir, "events.jsonl"),
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(c.Stop)
	srv := httptest.NewServer(daemon.NewHandler(c))
	t.Cleanup(srv.Close)
	return srv, c
}

func TestStatePrintsJSON(t *testing.T) {
	srv, _ := newServer(t)
	var out, errOut bytes.Buffer
	if code := run([]string{"state"}, &out, &errOut, srv.Client(), srv.URL); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	if !strings.Contains(out.String(), `"state": "idle"`) {
		t.Fatalf("unexpected output %q", out.String())
	}
}

func TestCmdRunsCommandAndPrintsMessage(t *testing.T) {
	srv, c := newServer(t)
	var out, errOut bytes.Buffer
	if code := run([]string{"cmd", "new-cycle"}, &out, &errOut, srv.Client(), srv.URL); code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	if !strings.Contains(out.String(), "New cycle started") {
		t.Fatalf("unexpected output %q", out.String())
	}
	if c.State().State.String() != "work" {
		t.Fatalf("core state %s", c.State().State)
	}
}

func TestCmdErrorExitsNonZero(t *testing.T) {
	srv, _ := newServer(t)
	var out, errOut bytes.Buffer
	if code := run([]string{"cmd", "pause"}, &out, &errOut, srv.Client(), srv.URL); code != 1 {
		t.Fatalf("expected exit 1, got %d", code)
	}
	if !strings.Contains(errOut.String(), "nothing to pause") {
		t.Fatalf("expected error on stderr, got %q", errOut.String())
	}
}

func TestEventsStreamsStates(t *testing.T) {
	srv, c := newServer(t)
	ctx, cancel := context.WithCancel(context.Background())
	var out, errOut bytes.Buffer
	done := make(chan int, 1)
	go func() { done <- runWithContext(ctx, []string{"events"}, &out, &errOut, srv.Client(), srv.URL) }()
	time.Sleep(100 * time.Millisecond)
	c.Execute("new-cycle")
	time.Sleep(100 * time.Millisecond)
	cancel()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("events did not stop on cancel")
	}
	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	if len(lines) < 2 || !strings.Contains(lines[0], `"state":"idle"`) || !strings.Contains(lines[1], `"state":"work"`) {
		t.Fatalf("unexpected lines %q", lines)
	}
}

func TestUsageOnUnknownSubcommand(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run([]string{"bogus"}, &out, &errOut, http.DefaultClient, "http://x"); code != 2 {
		t.Fatalf("expected exit 2, got %d", code)
	}
}
