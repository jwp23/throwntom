package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"runtime"
	"syscall"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/daemon"
	"github.com/jwp23/throwntom/v3/internal/notifier"
)

func main() {
	configPath := flag.String("config", "", "path to config toml")
	flag.Parse()

	resolvedConfig, err := config.ResolvePath(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}
	// A first run leaves the user a documented config to edit rather than
	// nothing at all. A file that already exists is untouched, and a path the
	// user named is never created: a typo there should fail loudly rather
	// than quietly start on defaults.
	if *configPath == "" {
		if err := config.EnsureFile(resolvedConfig); err != nil {
			fmt.Fprintf(os.Stderr, "config error: %v\n", err)
			os.Exit(1)
		}
	}
	cfg, err := config.LoadFile(resolvedConfig)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}
	paths, err := core.DefaultPaths()
	if err != nil {
		fmt.Fprintf(os.Stderr, "%v\n", err)
		os.Exit(1)
	}
	paths.Config = resolvedConfig
	n, err := notifier.NewSystemNotifier(runtime.GOOS, os.Stdout, cfg.SoundCommand)
	if err != nil {
		fmt.Fprintf(os.Stderr, "notifier error: %v\n", err)
		os.Exit(1)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	if err := daemon.Run(ctx, cfg, n, paths); err != nil {
		fmt.Fprintf(os.Stderr, "throwntomd: %v\n", err)
		os.Exit(1)
	}
}
