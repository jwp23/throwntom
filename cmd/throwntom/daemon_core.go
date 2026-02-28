package main

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/jwp23/throwntom/internal/app"
	"github.com/jwp23/throwntom/internal/config"
	"github.com/jwp23/throwntom/internal/notifier"
	"github.com/jwp23/throwntom/internal/reminder"
	"github.com/jwp23/throwntom/internal/scheduler"
)

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

type daemonCore struct {
	cycle          *app.App
	notifier       notifier.Notifier
	state          *daemonState
	scheduler      *scheduler.Scheduler
	repeatInterval time.Duration
	now            func() time.Time
}

func newDaemonCore(cfg config.Config, n notifier.Notifier) *daemonCore {
	repeatInterval := time.Duration(cfg.RepeatSecs) * time.Second
	return &daemonCore{
		cycle: app.New(
			cfg.WorkMinutes,
			cfg.ShortBreakMinutes,
			cfg.LongBreakMinutes,
			cfg.LongBreakEvery,
			repeatInterval,
			n,
		),
		notifier:       n,
		state:          &daemonState{},
		scheduler:      scheduler.New(cfg.Schedule.Days, cfg.Schedule.Time),
		repeatInterval: repeatInterval,
		now:            time.Now,
	}
}

func (d *daemonCore) start(ctx context.Context) {
	startMorningScheduler(ctx, d.state, d.scheduler, d.repeatInterval, d.notifier)
}

func (d *daemonCore) stop() {
	d.state.stopMorningLoop()
}

func (d *daemonCore) snapshot() (string, bool) {
	return d.state.statusSnapshot(d.cycle)
}

func (d *daemonCore) executeControlCommand(line string) daemonControlResponse {
	result := d.execute(line)
	statusLine, morningPending := d.snapshot()
	resp := daemonControlResponse{
		StatusLine:     statusLine,
		MorningPending: morningPending,
		Message:        result.message,
		Exit:           result.exit,
	}
	if result.err != nil {
		resp.Error = result.err.Error()
	}
	return resp
}

type daemonCommandResult struct {
	message string
	exit    bool
	err     error
}

func (d *daemonCore) execute(line string) daemonCommandResult {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" {
		return daemonCommandResult{}
	}
	parts := strings.Fields(trimmed)

	switch parts[0] {
	case "start":
		d.state.stopMorningLoop()
		d.state.clearSnooze()
		d.cycle.Start()
		return daemonCommandResult{message: "pomodoro started"}
	case "pause":
		d.cycle.Pause()
		return daemonCommandResult{message: "paused"}
	case "resume":
		d.cycle.Resume()
		return daemonCommandResult{message: "resumed"}
	case "stop":
		d.cycle.Stop()
		return daemonCommandResult{message: "stopped and returned to idle"}
	case "confirm":
		d.cycle.Confirm()
		return daemonCommandResult{message: fmt.Sprintf("confirmed, state=%s", d.cycle.Status())}
	case "snooze":
		parsed, err := parseSnoozeDuration(parts)
		if err != nil {
			return daemonCommandResult{err: err}
		}
		if d.state.isMorningPending() {
			d.state.stopMorningLoop()
			d.state.setSnoozeUntil(d.now().Add(parsed))
			return daemonCommandResult{message: fmt.Sprintf("morning reminder snoozed for %s", parsed)}
		}
		d.cycle.Snooze(parsed)
		return daemonCommandResult{message: fmt.Sprintf("cycle reminder snoozed for %s", parsed)}
	case "skip-today":
		d.state.stopMorningLoop()
		d.state.markSkippedToday(d.now())
		d.cycle.SkipToday()
		return daemonCommandResult{message: "skipped reminders for today"}
	case "test-sound":
		if err := d.notifier.PlaySound("test"); err != nil {
			return daemonCommandResult{message: fmt.Sprintf("sound test failed: %v", err)}
		}
		return daemonCommandResult{message: "sound test played"}
	case "status":
		return daemonCommandResult{}
	case "quit", "exit":
		d.state.stopMorningLoop()
		return daemonCommandResult{message: "bye", exit: true}
	default:
		return daemonCommandResult{err: fmt.Errorf("unknown command: %s", parts[0])}
	}
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

func startMorningLoop(state *daemonState, repeatInterval time.Duration, n notifier.Notifier) {
	ctx, shouldStart := state.beginMorningLoop()
	if !shouldStart {
		return
	}
	loop := reminder.New(repeatInterval, func() error {
		return n.PlaySound("morning")
	})
	go loop.Run(ctx)
}

func startMorningScheduler(ctx context.Context, state *daemonState, sched *scheduler.Scheduler, repeatInterval time.Duration, n notifier.Notifier) {
	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case now := <-ticker.C:
				if !state.shouldStartMorning(now, sched) {
					continue
				}
				startMorningLoop(state, repeatInterval, n)
			}
		}
	}()
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
		"  status             print current cycle status",
		"  test-sound         play reminder sound now",
		"  quit               stop daemon",
		"  exit               alias for quit",
	}, "\n")
}
