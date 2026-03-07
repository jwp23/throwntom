package main

import (
	"context"
	"fmt"
	"os"
	"runtime"
	"strings"

	"github.com/jwp23/throwntom/v2/internal/config"
	"github.com/jwp23/throwntom/v2/internal/notifier"
)

var runInteractiveUI = runInteractiveTea

func runLocalMode(cfg config.Config) {
	if err := requireInteractiveTTY(isTerminal(os.Stdin), isTerminal(os.Stdout)); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}

	core, err := buildTimerCore(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "notifier error: %v\n", err)
		os.Exit(1)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	core.start(ctx)
	defer core.stop()

	err = runInteractiveCallbacks(localModeCallbacks(cfg, core))
	if err != nil {
		fmt.Fprintf(os.Stderr, "input error: %v\n", err)
	}
}

func runInteractiveCallbacks(callbacks interactiveCallbacks) error {
	return runInteractiveUI(os.Stdout, os.Stdin, callbacks)
}

func localModeCallbacks(cfg config.Config, core *timerCore) interactiveCallbacks {
	header := []string{
		fmt.Sprintf("throwntom run mode started (schedule %s %s)", strings.Join(cfg.Schedule.Days, ","), cfg.Schedule.Time),
		fmt.Sprintf("cycle: work=%dm short=%dm long=%dm every=%d repeat=%ds", cfg.WorkMinutes, cfg.ShortBreakMinutes, cfg.LongBreakMinutes, cfg.LongBreakEvery, cfg.RepeatSecs),
	}

	return interactiveCallbacks{
		HeaderLines:    header,
		HelpLines:      strings.Split(commandsHelp(), "\n"),
		Emoji:          cfg.Emoji,
		StatusSnapshot: core.snapshot,
		FocusSnapshot: func() ([]string, string) {
			focusLines := core.formatFocusLines()
			focusPrompt := ""
			if core.isFocusPromptPending() {
				focusPrompt = core.formatFocusPrompt()
			}
			return focusLines, focusPrompt
		},
		Execute: func(command string) (commandResponse, error) {
			return core.executeCommand(command), nil
		},
		CancelFocus: func() commandResponse {
			result := core.cancelFocusPrompt()
			statusLine, engineState, morningPending := core.snapshot()
			return commandResponse{
				StatusLine:     statusLine,
				EngineState:    engineState,
				MorningPending: morningPending,
				Message:        result.message,
				FocusLines:     core.formatFocusLines(),
			}
		},
	}
}

func buildTimerCore(cfg config.Config) (*timerCore, error) {
	n, err := notifier.NewSystemNotifier(runtime.GOOS, os.Stdout, cfg.SoundCommand)
	if err != nil {
		return nil, err
	}
	core := newTimerCore(cfg, n)
	tasksPath, err := defaultTasksPath()
	if err != nil {
		return nil, err
	}
	if err := core.initTasks(tasksPath); err != nil {
		return nil, err
	}
	sessPath, err := defaultSessionPath()
	if err != nil {
		return nil, err
	}
	core.sessionPath = sessPath
	if err := core.loadSession(); err != nil {
		fmt.Fprintf(os.Stderr, "warning: could not load session: %v\n", err)
	}
	return core, nil
}

func requireInteractiveTTY(stdinTTY, stdoutTTY bool) error {
	if !stdinTTY || !stdoutTTY {
		return fmt.Errorf("throwntom requires an interactive terminal")
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
