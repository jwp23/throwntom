package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/jwp23/throwntom/internal/config"
)

func main() {
	flag.Usage = printFlagUsage
	configPath := flag.String("config", "", "path to config toml")
	socketPath := flag.String("socket", defaultSocketPath(), "path to daemon control unix socket")
	flag.Parse()

	inv, err := parseInvocation(flag.Args())
	if err != nil {
		fmt.Fprintf(os.Stderr, "argument error: %v\n", err)
		printUsage()
		os.Exit(1)
	}

	switch inv.mode {
	case modeControl:
		runControlMode(*socketPath, inv.controlCommand)
		return
	case modeShell:
		runShellMode(*socketPath)
		return
	}

	cfg, err := loadConfig(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}

	switch inv.mode {
	case modeRun:
		runLocalMode(cfg)
	case modeDaemon:
		runDaemonMode(cfg, *socketPath)
	default:
		fmt.Fprintf(os.Stderr, "argument error: unsupported mode %q\n", inv.mode)
		os.Exit(1)
	}
}

func loadConfig(path string) (config.Config, error) {
	if path == "" {
		defaultPath, err := defaultConfigPath()
		if err != nil {
			return config.Config{}, err
		}
		cfg, err := config.LoadFile(defaultPath)
		if err == nil {
			return cfg, nil
		}
		if errors.Is(err, os.ErrNotExist) {
			return config.Default(), nil
		}
		return config.Config{}, err
	}
	return config.LoadFile(path)
}

func defaultConfigPath() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home directory: %w", err)
	}
	return filepath.Join(homeDir, ".config", "throwntom", "config.toml"), nil
}

func printUsage() {
	fmt.Println("usage: throwntom [--config path] [--socket path] [run|daemon|shell|ctl <command...>]")
	fmt.Println()
	fmt.Println("modes:")
	fmt.Println("  run     run local interactive daemon in foreground (default)")
	fmt.Println("  daemon  run background-friendly daemon with unix socket control")
	fmt.Println("  shell   interactive terminal UI connected to running daemon")
	fmt.Println("  ctl     send a single command to running daemon")
	fmt.Println()
	fmt.Println(daemonCommandsHelp())
}

func printFlagUsage() {
	fmt.Fprintln(os.Stderr, "usage: throwntom [--config path] [--socket path] [run|daemon|shell|ctl <command...>]")
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, "options:")
	fmt.Fprintln(os.Stderr, "  --config string")
	fmt.Fprintln(os.Stderr, "        path to config toml (used by run/daemon)")
	fmt.Fprintln(os.Stderr, "  --socket string")
	fmt.Fprintln(os.Stderr, "        path to daemon control unix socket (used by daemon/shell/ctl)")
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, daemonCommandsHelp())
}
