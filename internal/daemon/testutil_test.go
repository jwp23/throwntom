package daemon

import (
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
)

type noopNotifier struct{}

func (noopNotifier) PlaySound(string) error { return nil }

func newTestCore(t *testing.T) *core.Core {
	t.Helper()
	dir := t.TempDir()
	cfg := config.Default()
	cfg.MorningReminderPending = false
	c, err := core.New(cfg, noopNotifier{}, core.Paths{
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

func newTestServer(t *testing.T) (*httptest.Server, *core.Core) {
	t.Helper()
	c := newTestCore(t)
	srv := httptest.NewServer(NewHandler(c))
	t.Cleanup(srv.Close)
	return srv, c
}
