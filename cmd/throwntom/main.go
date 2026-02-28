package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"os"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/jwp23/urgtomat/internal/app"
	"github.com/jwp23/urgtomat/internal/config"
	"github.com/jwp23/urgtomat/internal/notifier"
	"github.com/jwp23/urgtomat/internal/reminder"
	"github.com/jwp23/urgtomat/internal/scheduler"
)

func main() {
	flag.Usage = printFlagUsage
	configPath := flag.String("config", "", "path to config toml")
	flag.Parse()

	cfg, err := loadConfig(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}

	if flag.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "unexpected positional arguments")
		printUsage()
		os.Exit(1)
	}

	runDaemon(cfg)
}

func loadConfig(path string) (config.Config, error) {
	if path == "" {
		return config.Default(), nil
	}
	return config.LoadFile(path)
}

func runDaemon(cfg config.Config) {
	if err := requireInteractiveTTY(isTerminal(os.Stdin), isTerminal(os.Stdout)); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}

	n, err := notifier.NewSystemNotifier(runtime.GOOS, os.Stdout, cfg.SoundCommand)
	if err != nil {
		fmt.Fprintf(os.Stderr, "notifier error: %v\n", err)
		os.Exit(1)
	}
	cycle := app.New(
		cfg.WorkMinutes,
		cfg.ShortBreakMinutes,
		cfg.LongBreakMinutes,
		cfg.LongBreakEvery,
		time.Duration(cfg.RepeatSecs)*time.Second,
		n,
	)
	s := scheduler.New(cfg.Schedule.Days, cfg.Schedule.Time)

	fmt.Printf("throwntom daemon started (schedule %s %s)\n", strings.Join(cfg.Schedule.Days, ","), cfg.Schedule.Time)
	fmt.Printf("cycle: work=%dm short=%dm long=%dm every=%d repeat=%ds\n", cfg.WorkMinutes, cfg.ShortBreakMinutes, cfg.LongBreakMinutes, cfg.LongBreakEvery, cfg.RepeatSecs)
	fmt.Println(daemonCommandsHelp())

	ui := newTerminalUI(os.Stdout)

	var stateMu sync.Mutex
	var morningCancel context.CancelFunc
	var snoozeUntil time.Time
	lastTriggerDay := ""
	morningPending := false

	statusSnapshot := func() (string, bool) {
		stateMu.Lock()
		currentMorningPending := morningPending
		stateMu.Unlock()
		return cycle.StatusLine(), currentMorningPending
	}

	startMorningLoop := func() {
		var shouldStart bool
		var cancel context.CancelFunc

		stateMu.Lock()
		if morningPending {
			stateMu.Unlock()
			return
		}
		morningPending = true
		ctx, newCancel := context.WithCancel(context.Background())
		cancel = newCancel
		morningCancel = cancel
		shouldStart = true
		stateMu.Unlock()

		if !shouldStart {
			return
		}

		ui.Println("morning reminder: start/snooze/skip-today")
		loop := reminder.New(time.Duration(cfg.RepeatSecs)*time.Second, func() error {
			return n.PlaySound("morning")
		})
		go loop.Run(ctx)
	}

	stopMorningLoop := func() {
		stateMu.Lock()
		cancel := morningCancel
		morningCancel = nil
		morningPending = false
		stateMu.Unlock()

		if cancel != nil {
			cancel()
		}
	}

	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for now := range ticker.C {
			shouldStart := false
			dayKey := now.Format("2006-01-02")
			stateMu.Lock()
			if !snoozeUntil.IsZero() && now.Before(snoozeUntil) {
				stateMu.Unlock()
				continue
			}
			if s.ShouldTrigger(now) && dayKey != lastTriggerDay {
				lastTriggerDay = dayKey
				shouldStart = true
			}
			stateMu.Unlock()

			if shouldStart {
				startMorningLoop()
			}
		}
	}()

	statusLine, currentMorningPending := statusSnapshot()
	ui.ShowFrame(statusLine, currentMorningPending)

	stopStatusUpdates := make(chan struct{})
	defer close(stopStatusUpdates)
	var commandProcessing atomic.Bool
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stopStatusUpdates:
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

	scanner := bufio.NewScanner(os.Stdin)
	shouldQuit := false
	for scanner.Scan() {
		commandProcessing.Store(true)
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			statusLine, currentMorningPending := statusSnapshot()
			ui.ShowFrame(statusLine, currentMorningPending)
			commandProcessing.Store(false)
			continue
		}
		parts := strings.Fields(line)
		switch parts[0] {
		case "start":
			stopMorningLoop()
			stateMu.Lock()
			snoozeUntil = time.Time{}
			stateMu.Unlock()
			cycle.Start()
			ui.Println("pomodoro started")
		case "pause":
			cycle.Pause()
			ui.Println("paused")
		case "resume":
			cycle.Resume()
			ui.Println("resumed")
		case "stop":
			cycle.Stop()
			ui.Println("stopped and returned to idle")
		case "confirm":
			cycle.Confirm()
			ui.Println(fmt.Sprintf("confirmed, state=%s", cycle.Status()))
		case "snooze":
			if len(parts) < 2 {
				ui.Println("usage: snooze <duration>")
				break
			}
			d, err := time.ParseDuration(parts[1])
			if err != nil {
				ui.Println(fmt.Sprintf("invalid duration: %v", err))
				break
			}
			stateMu.Lock()
			currentMorningPending := morningPending
			stateMu.Unlock()
			if currentMorningPending {
				stopMorningLoop()
				stateMu.Lock()
				snoozeUntil = time.Now().Add(d)
				stateMu.Unlock()
				ui.Println(fmt.Sprintf("morning reminder snoozed for %s", d))
				break
			}
			cycle.Snooze(d)
			ui.Println(fmt.Sprintf("cycle reminder snoozed for %s", d))
		case "skip-today":
			stopMorningLoop()
			stateMu.Lock()
			snoozeUntil = time.Time{}
			lastTriggerDay = time.Now().Format("2006-01-02")
			stateMu.Unlock()
			cycle.SkipToday()
			ui.Println("skipped reminders for today")
		case "test-sound":
			if err := n.PlaySound("test"); err != nil {
				ui.Println(fmt.Sprintf("sound test failed: %v", err))
				break
			}
			ui.Println("sound test played")
		case "quit", "exit":
			stopMorningLoop()
			ui.Println("bye")
			shouldQuit = true
		default:
			ui.Println(fmt.Sprintf("unknown command: %s", parts[0]))
		}
		if shouldQuit {
			commandProcessing.Store(false)
			return
		}
		statusLine, currentMorningPending := statusSnapshot()
		ui.ShowFrame(statusLine, currentMorningPending)
		commandProcessing.Store(false)
	}
	if err := scanner.Err(); err != nil {
		fmt.Fprintf(os.Stderr, "input error: %v\n", err)
	}
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

func printUsage() {
	fmt.Println("usage: throwntom [--config path]")
	fmt.Println()
	fmt.Println(daemonCommandsHelp())
}

func printFlagUsage() {
	fmt.Fprintln(os.Stderr, "usage: throwntom [--config path]")
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, "options:")
	fmt.Fprintln(os.Stderr, "  --config string")
	fmt.Fprintln(os.Stderr, "        path to config toml")
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, daemonCommandsHelp())
}

func daemonCommandsHelp() string {
	return strings.Join([]string{
		"daemon commands:",
		"  start              start a new pomodoro",
		"  pause              pause the active pomodoro or break timer",
		"  resume             resume a paused pomodoro or break timer",
		"  stop               stop active timer and return to idle",
		"  confirm            acknowledge transition and move to next phase",
		"  snooze <duration>  delay reminders (example: snooze 10m)",
		"  skip-today         disable reminders and cycle for the rest of today",
		"  test-sound         play reminder sound now",
		"  quit               exit daemon",
	}, "\n")
}
