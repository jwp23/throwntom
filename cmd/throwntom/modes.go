package main

import (
	"context"
	"fmt"
	"os"
	"runtime"
	"strings"

	"github.com/jwp23/throwntom/internal/config"
	"github.com/jwp23/throwntom/internal/notifier"
)

var runInteractiveUI = runInteractiveTea

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

func localModeCallbacks(cfg config.Config, core *daemonCore) interactiveCallbacks {
	header := []string{
		fmt.Sprintf("throwntom run mode started (schedule %s %s)", strings.Join(cfg.Schedule.Days, ","), cfg.Schedule.Time),
		fmt.Sprintf("cycle: work=%dm short=%dm long=%dm every=%d repeat=%ds", cfg.WorkMinutes, cfg.ShortBreakMinutes, cfg.LongBreakMinutes, cfg.LongBreakEvery, cfg.RepeatSecs),
	}

	return interactiveCallbacks{
		HeaderLines:    header,
		HelpLines:      strings.Split(daemonCommandsHelp(), "\n"),
		StatusSnapshot: core.snapshot,
		FocusSnapshot: func() ([]string, string) {
			focusLines := core.formatFocusLines()
			focusPrompt := ""
			if core.isFocusPromptPending() {
				focusPrompt = core.formatFocusPrompt()
			}
			return focusLines, focusPrompt
		},
		Execute: func(command string) (daemonControlResponse, error) {
			return core.executeControlCommand(command), nil
		},
		CancelFocus: func() daemonControlResponse {
			result := core.cancelFocusPrompt()
			statusLine, morningPending := core.snapshot()
			return daemonControlResponse{
				StatusLine:     statusLine,
				MorningPending: morningPending,
				Message:        result.message,
				FocusLines:     core.formatFocusLines(),
			}
		},
	}
}

func buildDaemonCore(cfg config.Config) (*daemonCore, error) {
	n, err := notifier.NewSystemNotifier(runtime.GOOS, os.Stdout, cfg.SoundCommand)
	if err != nil {
		return nil, err
	}
	core := newDaemonCore(cfg, n)
	tasksPath, err := defaultTasksPath()
	if err != nil {
		return nil, err
	}
	if err := core.initTasks(tasksPath); err != nil {
		return nil, err
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
