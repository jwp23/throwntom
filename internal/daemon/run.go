package daemon

import (
	"context"
	"errors"
	"net"
	"net/http"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/notifier"
)

// Run serves the daemon API on paths.Socket until ctx is cancelled, then
// shuts the server down and stops the core, which saves the session.
func Run(ctx context.Context, cfg config.Config, n notifier.Notifier, paths core.Paths) error {
	c, err := core.New(cfg, n, paths)
	if err != nil {
		return err
	}
	ln, err := Listen(paths)
	if err != nil {
		return err
	}
	c.Start(ctx)
	srv := &http.Server{
		Handler:           NewHandler(c),
		ReadHeaderTimeout: 5 * time.Second,
		BaseContext:       func(net.Listener) context.Context { return ctx },
	}
	// Keep-alive connections over the unix socket can sit idle and, on this
	// platform, are not reliably detected/closed by Shutdown's idle-connection
	// sweep, which then blocks for the full grace period below. Since every
	// client here is local (CLI/TUI/native client over one socket), the cost
	// of a fresh connection per request is negligible, so disable keep-alives
	// outright rather than depend on Shutdown to reclaim idle connections.
	srv.SetKeepAlivesEnabled(false)
	errCh := make(chan error, 1)
	go func() { errCh <- srv.Serve(ln) }()

	select {
	case <-ctx.Done():
	case err := <-errCh:
		c.Stop()
		return err
	}
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	err = srv.Shutdown(shutdownCtx)
	c.Stop()
	if errors.Is(err, context.DeadlineExceeded) {
		_ = srv.Close() // SSE clients hold connections open; force them closed
		err = nil
	}
	return err
}
