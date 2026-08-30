package daemon

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/notifier"
)

// shutdownGrace bounds how long Run waits for srv.Shutdown to finish
// gracefully before forcing lingering connections closed.
const shutdownGrace = time.Second

// configPollInterval is how often the daemon looks at its config file. It is
// a variable so a test can poll faster than a person can type.
var configPollInterval = config.DefaultWatchInterval

// watchConfig applies edits to the config file at path to c, and returns a
// func that stops watching and waits for the watcher to be done — no config
// can reach the core after it returns, so shutdown cannot race a reload.
//
// baseline must be the exact bytes c's config was built from, not a fresh
// read of path: reading path again here, after core.New and c.Start have
// already run, would let an edit that landed in that window go uncounted —
// the watcher would treat the edited file as the baseline already in force
// and never report it.
func watchConfig(ctx context.Context, path string, baseline []byte, c *core.Core) func() {
	w := config.Watcher{
		Path:     path,
		Interval: configPollInterval,
		OnChange: c.ApplyConfig,
		OnError: func(err error) {
			fmt.Fprintf(os.Stderr, "throwntomd: keeping the current config: %v\n", err)
		},
	}
	watchCtx, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() {
		defer close(done)
		w.Run(watchCtx, baseline)
	}()
	return func() {
		cancel()
		<-done
	}
}

// Run serves the daemon API on paths.Socket until ctx is cancelled, then
// shuts the server down and stops the core, which saves the session.
//
// configBytes are the bytes cfg was decoded from — the watcher's baseline,
// so it agrees with the core on what is already in force. It is ignored
// when paths.Config is empty.
func Run(ctx context.Context, cfg config.Config, n notifier.Notifier, paths core.Paths, configBytes []byte) error {
	// The lock comes first: building the core loads and rewrites the session
	// and can fire notifications, which a losing second instance must not do.
	ln, err := Listen(paths)
	if err != nil {
		return err
	}
	c, err := core.New(cfg, n, paths)
	if err != nil {
		_ = ln.Close()
		return err
	}
	c.Start(ctx)
	stopWatching := func() {}
	if paths.Config != "" {
		stopWatching = watchConfig(ctx, paths.Config, configBytes, c)
	}
	srv := &http.Server{
		Handler:           NewHandler(c),
		ReadHeaderTimeout: 5 * time.Second,
		BaseContext:       func(net.Listener) context.Context { return ctx },
	}
	errCh := make(chan error, 1)
	go func() { errCh <- srv.Serve(ln) }()

	select {
	case <-ctx.Done():
	case err := <-errCh:
		stopWatching()
		c.Stop()
		return err
	}
	stopWatching()
	// WithoutCancel: ctx is already Done here (see the select above), so a plain
	// child of ctx would inherit that cancellation and skip the shutdown grace
	// period entirely. Detaching from ctx's cancellation keeps that grace period
	// while still rooting the timeout in the caller's context.
	shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), shutdownGrace)
	defer cancel()
	err = srv.Shutdown(shutdownCtx)
	c.Stop()
	if errors.Is(err, context.DeadlineExceeded) {
		// Close reclaims SSE streams and client-dialled-but-unused (StateNew)
		// connections that Shutdown will not touch for 5s.
		_ = srv.Close()
		fmt.Fprintln(os.Stderr, "throwntomd: forced close of lingering connections")
		err = nil
	}
	return err
}
