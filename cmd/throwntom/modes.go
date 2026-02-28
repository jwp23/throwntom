package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/jwp23/throwntom/internal/config"
	"github.com/jwp23/throwntom/internal/notifier"
)

func runLocalMode(cfg config.Config) {
	if err := requireInteractiveTTY(isTerminal(os.Stdin), isTerminal(os.Stdout)); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}

	core, err := buildDaemonCore(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "notifier error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("throwntom run mode started (schedule %s %s)\n", strings.Join(cfg.Schedule.Days, ","), cfg.Schedule.Time)
	fmt.Printf("cycle: work=%dm short=%dm long=%dm every=%d repeat=%ds\n", cfg.WorkMinutes, cfg.ShortBreakMinutes, cfg.LongBreakMinutes, cfg.LongBreakEvery, cfg.RepeatSecs)
	fmt.Println(daemonCommandsHelp())

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	core.start(ctx)
	defer core.stop()

	ui := newTerminalUI(os.Stdout)
	initial := core.executeControlCommand("status")
	ui.ShowFrame(initial.StatusLine, initial.MorningPending)

	stopStatusUpdates := make(chan struct{})
	defer close(stopStatusUpdates)
	var commandProcessing atomic.Bool
	startStatusUpdater(ui, core.snapshot, &commandProcessing, stopStatusUpdates)

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		commandProcessing.Store(true)
		resp := core.executeControlCommand(scanner.Text())
		renderResponseMessage(ui, resp)
		ui.ShowFrame(resp.StatusLine, resp.MorningPending)
		commandProcessing.Store(false)
		if resp.Exit {
			return
		}
	}
	if err := scanner.Err(); err != nil {
		fmt.Fprintf(os.Stderr, "input error: %v\n", err)
	}
}

func runDaemonMode(cfg config.Config, socketPath string) {
	core, err := buildDaemonCore(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "notifier error: %v\n", err)
		os.Exit(1)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	fmt.Printf("throwntom daemon started (schedule %s %s)\n", strings.Join(cfg.Schedule.Days, ","), cfg.Schedule.Time)
	fmt.Printf("cycle: work=%dm short=%dm long=%dm every=%d repeat=%ds\n", cfg.WorkMinutes, cfg.ShortBreakMinutes, cfg.LongBreakMinutes, cfg.LongBreakEvery, cfg.RepeatSecs)
	fmt.Printf("control socket: %s\n", socketPath)

	if err := serveDaemonSocket(ctx, cancel, core, socketPath); err != nil {
		fmt.Fprintf(os.Stderr, "daemon error: %v\n", err)
		os.Exit(1)
	}
}

func runShellMode(socketPath string) {
	if err := requireInteractiveTTY(isTerminal(os.Stdin), isTerminal(os.Stdout)); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}

	initial, err := sendControlCommand(socketPath, "status")
	if err != nil {
		fmt.Fprintf(os.Stderr, "control error: %v\n", err)
		os.Exit(1)
	}
	if initial.Error != "" {
		fmt.Fprintln(os.Stderr, initial.Error)
		os.Exit(1)
	}

	fmt.Printf("throwntom shell connected to daemon at %s\n", socketPath)
	fmt.Println(daemonCommandsHelp())

	ui := newTerminalUI(os.Stdout)
	cache := newStatusCache(initial.StatusLine, initial.MorningPending)
	ui.ShowFrame(initial.StatusLine, initial.MorningPending)

	stopStatusUpdates := make(chan struct{})
	defer close(stopStatusUpdates)
	var commandProcessing atomic.Bool
	statusSnapshot := func() (string, bool) {
		resp, err := sendControlCommand(socketPath, "status")
		if err == nil && resp.Error == "" {
			cache.Set(resp.StatusLine, resp.MorningPending)
		}
		return cache.Get()
	}
	startStatusUpdater(ui, statusSnapshot, &commandProcessing, stopStatusUpdates)

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		commandProcessing.Store(true)
		resp, err := sendControlCommand(socketPath, scanner.Text())
		if err != nil {
			ui.Println(fmt.Sprintf("control error: %v", err))
			statusLine, morningPending := cache.Get()
			ui.ShowFrame(statusLine, morningPending)
			commandProcessing.Store(false)
			continue
		}
		cache.Set(resp.StatusLine, resp.MorningPending)
		renderResponseMessage(ui, resp)
		ui.ShowFrame(resp.StatusLine, resp.MorningPending)
		commandProcessing.Store(false)
		if resp.Exit {
			return
		}
	}
	if err := scanner.Err(); err != nil {
		fmt.Fprintf(os.Stderr, "input error: %v\n", err)
	}
}

func runControlMode(socketPath string, command string) {
	resp, err := sendControlCommand(socketPath, command)
	if err != nil {
		fmt.Fprintf(os.Stderr, "control error: %v\n", err)
		os.Exit(1)
	}
	if resp.Error != "" {
		fmt.Fprintln(os.Stderr, resp.Error)
		os.Exit(1)
	}

	if strings.TrimSpace(command) == "status" {
		fmt.Printf("%s morning reminder pending=%t\n", resp.StatusLine, resp.MorningPending)
		return
	}

	if resp.Message != "" {
		fmt.Println(resp.Message)
	}
	fmt.Printf("status: %s morning reminder pending=%t\n", resp.StatusLine, resp.MorningPending)
}

func buildDaemonCore(cfg config.Config) (*daemonCore, error) {
	n, err := notifier.NewSystemNotifier(runtime.GOOS, os.Stdout, cfg.SoundCommand)
	if err != nil {
		return nil, err
	}
	return newDaemonCore(cfg, n), nil
}

func serveDaemonSocket(ctx context.Context, cancel context.CancelFunc, core *daemonCore, socketPath string) error {
	if err := os.MkdirAll(filepath.Dir(socketPath), 0o755); err != nil {
		return fmt.Errorf("create socket directory: %w", err)
	}
	if err := removeSocketFile(socketPath); err != nil {
		return err
	}

	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		return fmt.Errorf("listen on socket %q: %w", socketPath, err)
	}
	defer func() {
		_ = listener.Close()
		_ = os.Remove(socketPath)
	}()

	if err := os.Chmod(socketPath, 0o600); err != nil {
		return fmt.Errorf("set socket permissions: %w", err)
	}

	core.start(ctx)
	defer core.stop()

	errCh := make(chan error, 1)
	go func() {
		<-ctx.Done()
		_ = listener.Close()
	}()
	go func() {
		errCh <- acceptControlConnections(listener, core, cancel)
	}()

	select {
	case <-ctx.Done():
		return nil
	case err := <-errCh:
		if errors.Is(err, net.ErrClosed) {
			return nil
		}
		return err
	}
}

func removeSocketFile(path string) error {
	err := os.Remove(path)
	if err == nil || errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return fmt.Errorf("remove existing socket %q: %w", path, err)
}

func acceptControlConnections(listener net.Listener, core *daemonCore, cancel context.CancelFunc) error {
	for {
		conn, err := listener.Accept()
		if err != nil {
			return err
		}
		go handleControlConnection(conn, core, cancel)
	}
}

func handleControlConnection(conn net.Conn, core *daemonCore, cancel context.CancelFunc) {
	defer func() {
		if closeErr := conn.Close(); closeErr != nil {
			fmt.Fprintf(os.Stderr, "warn: close control connection: %v\n", closeErr)
		}
	}()

	reader := bufio.NewReader(conn)
	line, err := reader.ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		_ = json.NewEncoder(conn).Encode(daemonControlResponse{
			Error: fmt.Sprintf("read command: %v", err),
		})
		return
	}

	resp := core.executeControlCommand(line)
	if err := json.NewEncoder(conn).Encode(resp); err != nil {
		return
	}
	if resp.Exit {
		cancel()
	}
}

func renderResponseMessage(ui *terminalUI, resp daemonControlResponse) {
	if resp.Error != "" {
		ui.Println(resp.Error)
		return
	}
	if resp.Message != "" {
		ui.Println(resp.Message)
	}
}

type statusCache struct {
	mu             sync.Mutex
	statusLine     string
	morningPending bool
}

func newStatusCache(statusLine string, morningPending bool) *statusCache {
	return &statusCache{
		statusLine:     statusLine,
		morningPending: morningPending,
	}
}

func (c *statusCache) Get() (string, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.statusLine, c.morningPending
}

func (c *statusCache) Set(statusLine string, morningPending bool) {
	c.mu.Lock()
	c.statusLine = statusLine
	c.morningPending = morningPending
	c.mu.Unlock()
}

func startStatusUpdater(ui *terminalUI, statusSnapshot func() (string, bool), commandProcessing *atomic.Bool, stop <-chan struct{}) {
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stop:
				return
			case <-ticker.C:
				if !shouldRenderStatus(commandProcessing.Load()) {
					continue
				}
				statusLine, currentMorningPending := statusSnapshot()
				ui.UpdateStatus(statusLine, currentMorningPending)
			}
		}
	}()
}

func shouldRenderStatus(commandProcessing bool) bool {
	return !commandProcessing
}

func requireInteractiveTTY(stdinTTY, stdoutTTY bool) error {
	if !stdinTTY || !stdoutTTY {
		return fmt.Errorf("daemon requires an interactive terminal")
	}
	return nil
}

func isTerminal(f *os.File) bool {
	info, err := f.Stat()
	if err != nil {
		return false
	}
	return (info.Mode() & os.ModeCharDevice) != 0
}
