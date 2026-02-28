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

	"github.com/jwp23/throwntom/internal/app"
	"github.com/jwp23/throwntom/internal/config"
	"github.com/jwp23/throwntom/internal/notifier"
	"github.com/jwp23/throwntom/internal/reminder"
	"github.com/jwp23/throwntom/internal/scheduler"
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

type daemonState struct {
	mu             sync.Mutex
	morningCancel  context.CancelFunc
	snoozeUntil    time.Time
	lastTriggerDay string
	morningPending bool
}

func (s *daemonState) statusSnapshot(cycle *app.App) (string, bool) {
	s.mu.Lock()
	currentMorningPending := s.morningPending
	s.mu.Unlock()
	return cycle.StatusLine(), currentMorningPending
}

func (s *daemonState) beginMorningLoop() (context.Context, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.morningPending {
		return nil, false
	}
	ctx, cancel := context.WithCancel(context.Background())
	s.morningPending = true
	s.morningCancel = cancel
	return ctx, true
}

func (s *daemonState) stopMorningLoop() {
	s.mu.Lock()
	cancel := s.morningCancel
	s.morningCancel = nil
	s.morningPending = false
	s.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func (s *daemonState) shouldStartMorning(now time.Time, sched *scheduler.Scheduler) bool {
	dayKey := now.Format("2006-01-02")
	s.mu.Lock()
	defer s.mu.Unlock()
	if !s.snoozeUntil.IsZero() && now.Before(s.snoozeUntil) {
		return false
	}
	if !sched.ShouldTrigger(now) || dayKey == s.lastTriggerDay {
		return false
	}
	s.lastTriggerDay = dayKey
	return true
}

func (s *daemonState) clearSnooze() {
	s.mu.Lock()
	s.snoozeUntil = time.Time{}
	s.mu.Unlock()
}

func (s *daemonState) setSnoozeUntil(until time.Time) {
	s.mu.Lock()
	s.snoozeUntil = until
	s.mu.Unlock()
}

func (s *daemonState) markSkippedToday(now time.Time) {
	s.mu.Lock()
	s.snoozeUntil = time.Time{}
	s.lastTriggerDay = now.Format("2006-01-02")
	s.mu.Unlock()
}

func (s *daemonState) isMorningPending() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.morningPending
}

type daemonRuntime struct {
	cycle    *app.App
	ui       *terminalUI
	notifier notifier.Notifier
	state    *daemonState
	now      func() time.Time
}

type daemonCommandHandler func(parts []string) bool

func startMorningLoop(state *daemonState, ui *terminalUI, repeatInterval time.Duration, n notifier.Notifier) {
	ctx, shouldStart := state.beginMorningLoop()
	if !shouldStart {
		return
	}
	ui.Println("morning reminder: start/snooze/skip-today")
	loop := reminder.New(repeatInterval, func() error {
		return n.PlaySound("morning")
	})
	go loop.Run(ctx)
}

func startMorningScheduler(state *daemonState, sched *scheduler.Scheduler, repeatInterval time.Duration, n notifier.Notifier, ui *terminalUI) {
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for now := range ticker.C {
			if !state.shouldStartMorning(now, sched) {
				continue
			}
			startMorningLoop(state, ui, repeatInterval, n)
		}
	}()
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

func handleStartCommand(rt daemonRuntime) {
	rt.state.stopMorningLoop()
	rt.state.clearSnooze()
	rt.cycle.Start()
	rt.ui.Println("pomodoro started")
}

func handlePauseCommand(rt daemonRuntime) {
	rt.cycle.Pause()
	rt.ui.Println("paused")
}

func handleResumeCommand(rt daemonRuntime) {
	rt.cycle.Resume()
	rt.ui.Println("resumed")
}

func handleStopCommand(rt daemonRuntime) {
	rt.cycle.Stop()
	rt.ui.Println("stopped and returned to idle")
}

func handleConfirmCommand(rt daemonRuntime) {
	rt.cycle.Confirm()
	rt.ui.Println(fmt.Sprintf("confirmed, state=%s", rt.cycle.Status()))
}

func parseSnoozeDuration(parts []string) (time.Duration, error) {
	if len(parts) < 2 {
		return 0, fmt.Errorf("usage: snooze <duration>")
	}
	d, err := time.ParseDuration(parts[1])
	if err != nil {
		return 0, fmt.Errorf("invalid duration: %v", err)
	}
	return d, nil
}

func handleSnoozeCommand(rt daemonRuntime, parts []string) {
	d, err := parseSnoozeDuration(parts)
	if err != nil {
		rt.ui.Println(err.Error())
		return
	}
	if rt.state.isMorningPending() {
		rt.state.stopMorningLoop()
		rt.state.setSnoozeUntil(rt.now().Add(d))
		rt.ui.Println(fmt.Sprintf("morning reminder snoozed for %s", d))
		return
	}
	rt.cycle.Snooze(d)
	rt.ui.Println(fmt.Sprintf("cycle reminder snoozed for %s", d))
}

func handleSkipTodayCommand(rt daemonRuntime) {
	rt.state.stopMorningLoop()
	rt.state.markSkippedToday(rt.now())
	rt.cycle.SkipToday()
	rt.ui.Println("skipped reminders for today")
}

func handleTestSoundCommand(rt daemonRuntime) {
	if err := rt.notifier.PlaySound("test"); err != nil {
		rt.ui.Println(fmt.Sprintf("sound test failed: %v", err))
		return
	}
	rt.ui.Println("sound test played")
}

func handleQuitCommand(rt daemonRuntime) {
	rt.state.stopMorningLoop()
	rt.ui.Println("bye")
}

func buildDaemonCommandHandlers(rt daemonRuntime) map[string]daemonCommandHandler {
	return map[string]daemonCommandHandler{
		"start": func(_ []string) bool {
			handleStartCommand(rt)
			return false
		},
		"pause": func(_ []string) bool {
			handlePauseCommand(rt)
			return false
		},
		"resume": func(_ []string) bool {
			handleResumeCommand(rt)
			return false
		},
		"stop": func(_ []string) bool {
			handleStopCommand(rt)
			return false
		},
		"confirm": func(_ []string) bool {
			handleConfirmCommand(rt)
			return false
		},
		"snooze": func(parts []string) bool {
			handleSnoozeCommand(rt, parts)
			return false
		},
		"skip-today": func(_ []string) bool {
			handleSkipTodayCommand(rt)
			return false
		},
		"test-sound": func(_ []string) bool {
			handleTestSoundCommand(rt)
			return false
		},
		"quit": func(_ []string) bool {
			handleQuitCommand(rt)
			return true
		},
		"exit": func(_ []string) bool {
			handleQuitCommand(rt)
			return true
		},
	}
}

func executeDaemonCommand(line string, handlers map[string]daemonCommandHandler, ui *terminalUI) bool {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" {
		return false
	}
	parts := strings.Fields(trimmed)
	handler, ok := handlers[parts[0]]
	if !ok {
		ui.Println(fmt.Sprintf("unknown command: %s", parts[0]))
		return false
	}
	return handler(parts)
}

func runDaemon(cfg config.Config) {
	if err := requireInteractiveTTY(isTerminal(os.Stdin), isTerminal(os.Stdout)); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}

	repeatInterval := time.Duration(cfg.RepeatSecs) * time.Second
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
		repeatInterval,
		n,
	)
	s := scheduler.New(cfg.Schedule.Days, cfg.Schedule.Time)

	fmt.Printf("throwntom daemon started (schedule %s %s)\n", strings.Join(cfg.Schedule.Days, ","), cfg.Schedule.Time)
	fmt.Printf("cycle: work=%dm short=%dm long=%dm every=%d repeat=%ds\n", cfg.WorkMinutes, cfg.ShortBreakMinutes, cfg.LongBreakMinutes, cfg.LongBreakEvery, cfg.RepeatSecs)
	fmt.Println(daemonCommandsHelp())

	ui := newTerminalUI(os.Stdout)
	state := &daemonState{}
	statusSnapshot := func() (string, bool) { return state.statusSnapshot(cycle) }
	startMorningScheduler(state, s, repeatInterval, n, ui)

	statusLine, currentMorningPending := statusSnapshot()
	ui.ShowFrame(statusLine, currentMorningPending)

	stopStatusUpdates := make(chan struct{})
	defer close(stopStatusUpdates)
	var commandProcessing atomic.Bool
	startStatusUpdater(ui, statusSnapshot, &commandProcessing, stopStatusUpdates)

	handlers := buildDaemonCommandHandlers(daemonRuntime{
		cycle:    cycle,
		ui:       ui,
		notifier: n,
		state:    state,
		now:      time.Now,
	})

	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		commandProcessing.Store(true)
		if executeDaemonCommand(scanner.Text(), handlers, ui) {
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
