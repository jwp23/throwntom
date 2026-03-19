package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/jwp23/throwntom/v3/internal/config"
)

var version = "3.1.0"

func main() {
	flag.Usage = printFlagUsage
	configPath := flag.String("config", "", "path to config toml")
	showVersion := flag.Bool("version", false, "print version and exit")
	flag.Parse()

	if *showVersion {
		fmt.Println(version)
		os.Exit(0)
	}

	if err := parseInvocation(flag.Args()); err != nil {
		fmt.Fprintf(os.Stderr, "argument error: %v\n", err)
		printUsage()
		os.Exit(1)
	}

	if err := ensureConfigDir(); err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}

	cfg, err := loadConfig(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}

	run(cfg)
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

func ensureConfigDir() error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("resolve home directory: %w", err)
	}
	dir := filepath.Join(homeDir, ".config", "throwntom")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return fmt.Errorf("create config directory: %w", err)
	}
	return nil
}

func configDirPath(filename string) (string, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home directory: %w", err)
	}
	return filepath.Join(homeDir, ".config", "throwntom", filename), nil
}

func defaultConfigPath() (string, error) {
	return configDirPath("config.toml")
}

func defaultTasksPath() (string, error) {
	return configDirPath("tasks.json")
}

func defaultSessionPath() (string, error) {
	return configDirPath("session.json")
}

func defaultEventsPath() (string, error) {
	return configDirPath("events.jsonl")
}

func printUsage() {
	fmt.Println("usage: throwntom [--version] [--config path]")
}

func printFlagUsage() {
	fmt.Fprintln(os.Stderr, "usage: throwntom [--version] [--config path]")
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, "options:")
	fmt.Fprintln(os.Stderr, "  --config string")
	fmt.Fprintln(os.Stderr, "        path to config toml")
	fmt.Fprintln(os.Stderr, "  --version")
	fmt.Fprintln(os.Stderr, "        print version and exit")
}
