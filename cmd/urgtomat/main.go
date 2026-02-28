package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"urgtomat/internal/app"
	"urgtomat/internal/config"
	"urgtomat/internal/notifier"
	"urgtomat/internal/reminder"
	"urgtomat/internal/scheduler"
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

	n := notifier.NewMacOSNotifier()
	cycle := app.New(
		cfg.WorkMinutes,
		cfg.ShortBreakMinutes,
		cfg.LongBreakMinutes,
		cfg.LongBreakEvery,
		time.Duration(cfg.RepeatSecs)*time.Second,
		n,
	)
	s := scheduler.New(cfg.Schedule.Days, cfg.Schedule.Time)

	fmt.Printf("urgtomat daemon started (schedule %s %s)\n", strings.Join(cfg.Schedule.Days, ","), cfg.Schedule.Time)
	fmt.Printf("cycle: work=%dm short=%dm long=%dm every=%d repeat=%ds\n", cfg.WorkMinutes, cfg.ShortBreakMinutes, cfg.LongBreakMinutes, cfg.LongBreakEvery, cfg.RepeatSecs)
	fmt.Println(daemonCommandsHelp())

	var stateMu sync.Mutex
	var morningCancel context.CancelFunc
	var snoozeUntil time.Time
	lastTriggerDay := ""
	morningPending := false

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

		fmt.Println("\nmorning reminder: start/snooze/skip-today")
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

	scanner := bufio.NewScanner(os.Stdin)
	shouldQuit := false
	for {
		fmt.Print("\ncommand> ")
		if !scanner.Scan() {
			fmt.Println()
			return
		}
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		func() {
			switch parts[0] {
			case "start":
				stopMorningLoop()
				stateMu.Lock()
				snoozeUntil = time.Time{}
				stateMu.Unlock()
				cycle.Start()
				fmt.Println("pomodoro started")
			case "pause":
				cycle.Pause()
				fmt.Println("paused")
			case "resume":
				cycle.Resume()
				fmt.Println("resumed")
			case "stop":
				cycle.Stop()
				fmt.Println("stopped and returned to idle")
			case "confirm":
				cycle.Confirm()
				fmt.Printf("confirmed, state=%s\n", cycle.Status())
			case "snooze":
				if len(parts) < 2 {
					fmt.Println("usage: snooze <duration>")
					return
				}
				d, err := time.ParseDuration(parts[1])
				if err != nil {
					fmt.Printf("invalid duration: %v\n", err)
					return
				}
				stateMu.Lock()
				currentMorningPending := morningPending
				stateMu.Unlock()
				if currentMorningPending {
					stopMorningLoop()
					stateMu.Lock()
					snoozeUntil = time.Now().Add(d)
					stateMu.Unlock()
					fmt.Printf("morning reminder snoozed for %s\n", d)
					return
				}
				cycle.Snooze(d)
				fmt.Printf("cycle reminder snoozed for %s\n", d)
			case "skip-today":
				stopMorningLoop()
				stateMu.Lock()
				snoozeUntil = time.Time{}
				lastTriggerDay = time.Now().Format("2006-01-02")
				stateMu.Unlock()
				cycle.SkipToday()
				fmt.Println("skipped reminders for today")
			case "status":
				stateMu.Lock()
				currentMorningPending := morningPending
				stateMu.Unlock()
				fmt.Printf("%s morning_pending=%t\n", cycle.StatusLine(), currentMorningPending)
			case "help":
				fmt.Println(daemonCommandsHelp())
			case "quit", "exit":
				stopMorningLoop()
				fmt.Println("bye")
				shouldQuit = true
			default:
				fmt.Printf("unknown command: %s\n", parts[0])
			}
		}()
		if shouldQuit {
			return
		}
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
	fmt.Println("usage: urgtomat [--config path]")
	fmt.Println()
	fmt.Println(daemonCommandsHelp())
}

func printFlagUsage() {
	fmt.Fprintln(os.Stderr, "usage: urgtomat [--config path]")
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
		"  status             print current status line",
		"  help               show command descriptions",
		"  quit               exit daemon",
	}, "\n")
}
