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
	flag.Parse()

	inv, err := parseInvocation(flag.Args())
	if err != nil {
		fmt.Fprintf(os.Stderr, "argument error: %v\n", err)
		printUsage()
		os.Exit(1)
	}

	cfg, err := loadConfig(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}

	switch inv.mode {
	case modeRun:
		runLocalMode(cfg)
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

func defaultTasksPath() (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home directory: %w", err)
	}
	return filepath.Join(homeDir, ".config", "throwntom", "tasks.json"), nil
}

func printUsage() {
	fmt.Println("usage: throwntom [--config path] [run]")
	fmt.Println()
	fmt.Println("modes:")
	fmt.Println("  run     run interactive pomodoro timer (default)")
	fmt.Println()
	fmt.Println(daemonCommandsHelp())
}

func printFlagUsage() {
	fmt.Fprintln(os.Stderr, "usage: throwntom [--config path] [run]")
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, "options:")
	fmt.Fprintln(os.Stderr, "  --config string")
	fmt.Fprintln(os.Stderr, "        path to config toml")
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, daemonCommandsHelp())
}
