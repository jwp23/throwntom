package main

import (
	"context"
	"fmt"
	"os"
	"runtime"
	"strings"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/notifier"
)

var runInteractiveUI = runInteractiveTea

func run(cfg config.Config) {
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

	err = runInteractiveCallbacks(buildCallbacks(cfg, core))
	if err != nil {
		fmt.Fprintf(os.Stderr, "input error: %v\n", err)
	}
}

func runInteractiveCallbacks(callbacks interactiveCallbacks) error {
	return runInteractiveUI(os.Stdout, os.Stdin, callbacks)
}

func buildCallbacks(cfg config.Config, core *timerCore) interactiveCallbacks {
	header := []string{
		fmt.Sprintf("%s throwntom (%s)", stateIcon(engine.Idle, cfg.Emoji), formatScheduleHeader(cfg.Schedule)),
		fmt.Sprintf("%dm work / %dm short / %dm long / every %d", cfg.Pomodoro.WorkMinutes, cfg.Pomodoro.ShortBreakMinutes, cfg.Pomodoro.LongBreakMinutes, cfg.Pomodoro.LongBreakEvery),
	}

	render := func(resp commandResponse) commandResponse {
		resp.FocusLines = formatFocusLines(resp.Focused, cfg.Emoji)
		if resp.Stats != nil {
			resp.StatsView = renderDashboard(*resp.Stats, core.now(), cfg.Stats.TierLow, cfg.Stats.TierMid)
		}
		return resp
	}
	return interactiveCallbacks{
		HeaderLines:    header,
		HelpLines:      strings.Split(commandsHelp(), "\n"),
		Emoji:          cfg.Emoji,
		StatusSnapshot: core.snapshot,
		SecondaryStatus: func() string {
			next, dur, ok := core.nextStage()
			if !ok {
				return ""
			}
			return nextStageLabel(next, dur)
		},
		FocusSnapshot: func() ([]string, string) {
			focusPrompt := ""
			if core.isFocusPromptPending() {
				focusPrompt = core.formatFocusPrompt()
			}
			return formatFocusLines(core.focusedTasks(), cfg.Emoji), focusPrompt
		},
		Execute: func(command string) (commandResponse, error) {
			return render(core.executeCommand(command)), nil
		},
		CancelFocus: func() commandResponse {
			result := core.cancelFocusPrompt()
			statusLine, engineState, morningPending := core.snapshot()
			return render(commandResponse{
				StatusLine:     statusLine,
				EngineState:    engineState,
				MorningPending: morningPending,
				Message:        result.message,
				Focused:        core.focusedTasks(),
			})
		},
	}
}

func buildTimerCore(cfg config.Config) (*timerCore, error) {
	n, err := notifier.NewSystemNotifier(runtime.GOOS, os.Stdout, cfg.SoundCommand)
	if err != nil {
		return nil, err
	}
	paths, err := defaultCorePaths()
	if err != nil {
		return nil, err
	}
	return openTimerCore(cfg, n, paths)
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

func formatScheduleHeader(entries []config.ScheduleEntry) string {
	groups := make([]string, len(entries))
	for i, e := range entries {
		groups[i] = strings.Join(e.Days, ",") + " " + e.Time
	}
	return strings.Join(groups, " | ")
}
