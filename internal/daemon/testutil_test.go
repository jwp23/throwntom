package daemon

import (
	"context"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/notifier"
)

type noopNotifier struct{}

func (noopNotifier) PlaySound(string) error { return nil }

// soundingNotifier stands in for a composition root that gave the daemon an
// audible notifier, which daemon.Run accepts. It records what it played.
type soundingNotifier struct {
	played chan string
}

func (n soundingNotifier) PlaySound(name string) error {
	n.played <- name
	return nil
}

func newTestCore(t *testing.T) *core.Core {
	t.Helper()
	// notifier.Silent() is what cmd/throwntomd injects, so what the daemon
	// refuses to do with sound is decided the way it is in production.
	return newTestCoreWithNotifier(t, notifier.Silent())
}

func newTestCoreWithNotifier(t *testing.T, n notifier.Notifier) *core.Core {
	t.Helper()
	dir := t.TempDir()
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c, err := core.New(cfg, n, core.Paths{
		Tasks:   filepath.Join(dir, "tasks.json"),
		Session: filepath.Join(dir, "session.json"),
		Events:  filepath.Join(dir, "events.jsonl"),
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(c.Stop)
	return c
}

func newTestCoreWithMorning(t *testing.T) *core.Core {
	t.Helper()
	dir := t.TempDir()
	cfg := config.Default()
	cfg.MorningReminderPending = true
	// A schedule active every day at midnight keeps Start raising the
	// morning reminder deterministically, regardless of when the test runs.
	cfg.Schedule = []config.ScheduleEntry{{
		Days: []string{"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"},
		Time: "00:00",
	}}
	c, err := core.New(cfg, noopNotifier{}, core.Paths{
		Tasks:   filepath.Join(dir, "tasks.json"),
		Session: filepath.Join(dir, "session.json"),
		Events:  filepath.Join(dir, "events.jsonl"),
	})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	c.Start(ctx)
	t.Cleanup(func() { cancel(); c.Stop() })
	return c
}

func newTestServer(t *testing.T) (*httptest.Server, *core.Core) {
	t.Helper()
	c := newTestCore(t)
	srv := httptest.NewServer(NewHandler(c))
	t.Cleanup(srv.Close)
	return srv, c
}
