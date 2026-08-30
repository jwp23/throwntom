package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/daemon"
	"github.com/jwp23/throwntom/v3/internal/notifier"
)

func main() {
	configPath := flag.String("config", "", "path to config toml")
	flag.Parse()

	cfg, err := config.LoadDefault(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}
	paths, err := core.DefaultPaths()
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	if err := daemon.Run(ctx, cfg, daemonNotifier(), paths); err != nil {
		fmt.Fprintf(os.Stderr, "throwntomd: %v\n", err)
		os.Exit(1)
	}
}

// daemonNotifier is the daemon's whole side of reminder sound: none of it.
// ADR-003 gives presentation to the clients, and the daemon runs where no
// user is present to answer what it would play. Sound is the client's, as the
// banner already is; the daemon publishes the state both are raised from.
func daemonNotifier() notifier.Notifier {
	return notifier.Silent()
}
