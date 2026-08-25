package main

import (
	"context"
	"fmt"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/notifier"
)

var runInteractiveUI = runInteractiveTea

func run(cfg config.Config) {
	if err := requireInteractiveTTY(isTerminal(os.Stdin), isTerminal(os.Stdout)); err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}

	c, err := buildTimerCore(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "notifier error: %v\n", err)
		os.Exit(1)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c.Start(ctx)
	defer c.Stop()

	err = runInteractiveCallbacks(buildCallbacks(cfg, c))
	if err != nil {
		fmt.Fprintf(os.Stderr, "input error: %v\n", err)
	}
}

func runInteractiveCallbacks(callbacks interactiveCallbacks) error {
	return runInteractiveUI(os.Stdout, os.Stdin, callbacks)
}

func buildCallbacks(cfg config.Config, c *core.Core) interactiveCallbacks {
	header := []string{
		fmt.Sprintf("%s throwntom (%s)", stateIcon(engine.Idle, cfg.Emoji), formatScheduleHeader(cfg.Schedule)),
		fmt.Sprintf("%dm work / %dm short / %dm long / every %d", cfg.Pomodoro.WorkMinutes, cfg.Pomodoro.ShortBreakMinutes, cfg.Pomodoro.LongBreakMinutes, cfg.Pomodoro.LongBreakEvery),
	}

	render := func(r core.Response) commandResponse {
		resp := commandResponse{Response: r, FocusLines: formatFocusLines(r.Focused, cfg.Emoji)}
		if r.Stats != nil {
			resp.StatsView = renderDashboard(*r.Stats, time.Now(), cfg.Stats.TierLow, cfg.Stats.TierMid)
		}
		return resp
	}
	return interactiveCallbacks{
		HeaderLines:    header,
		HelpLines:      strings.Split(core.Help(), "\n"),
		Emoji:          cfg.Emoji,
		StatusSnapshot: c.Status,
		SecondaryStatus: func() string {
			next, dur, ok := c.NextStage()
			if !ok {
				return ""
			}
			return nextStageLabel(next, dur)
		},
		FocusSnapshot: func() ([]string, string) {
			focusPrompt := ""
			if c.FocusPromptPending() {
				focusPrompt = c.FocusPrompt()
			}
			return formatFocusLines(c.Focused(), cfg.Emoji), focusPrompt
		},
		Execute: func(command string) (commandResponse, error) {
			return render(c.Execute(command)), nil
		},
		CancelFocus: func() commandResponse {
			return render(c.CancelFocus())
		},
	}
}

func buildTimerCore(cfg config.Config) (*core.Core, error) {
	n, err := notifier.NewSystemNotifier(runtime.GOOS, os.Stdout, cfg.SoundCommand)
	if err != nil {
		return nil, err
	}
	paths, err := core.DefaultPaths()
	if err != nil {
		return nil, err
	}
	return core.New(cfg, n, paths)
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
