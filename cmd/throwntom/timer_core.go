package main

import (
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/jwp23/throwntom/v3/internal/app"
	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/notifier"
	"github.com/jwp23/throwntom/v3/internal/reminder"
	"github.com/jwp23/throwntom/v3/internal/scheduler"
	"github.com/jwp23/throwntom/v3/internal/session"
	"github.com/jwp23/throwntom/v3/internal/task"
)

type reminderState struct {
	mu             sync.Mutex
	morningCancel  context.CancelFunc
	snoozeUntil    time.Time
	lastTriggerDay string
	morningPending bool
}

func (s *reminderState) statusSnapshot(cycle *app.App) (string, engine.State, bool) {
	s.mu.Lock()
	currentMorningPending := s.morningPending
	s.mu.Unlock()
	return cycle.StatusLine(), cycle.State(), currentMorningPending
}

func (s *reminderState) beginMorningLoop() (context.Context, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.morningCancel != nil {
		return nil, false
	}
	ctx, cancel := context.WithCancel(context.Background())
	s.morningPending = true
	s.morningCancel = cancel
	return ctx, true
}

func (s *reminderState) stopMorningLoop() {
	s.mu.Lock()
	cancel := s.morningCancel
	s.morningCancel = nil
	s.morningPending = false
	s.mu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func (s *reminderState) shouldStartMorning(now time.Time, sched *scheduler.Scheduler) bool {
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

func (s *reminderState) clearSnooze() {
	s.mu.Lock()
	s.snoozeUntil = time.Time{}
	s.mu.Unlock()
}

func (s *reminderState) setSnoozeUntil(until time.Time) {
	s.mu.Lock()
	s.snoozeUntil = until
	s.mu.Unlock()
}

func (s *reminderState) markSkippedToday(now time.Time) {
	s.mu.Lock()
	s.snoozeUntil = time.Time{}
	s.lastTriggerDay = now.Format("2006-01-02")
	s.mu.Unlock()
}

func (s *reminderState) isMorningPending() bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.morningPending
}

type timerCore struct {
	cycle               *app.App
	notifier            notifier.Notifier
	state               *reminderState
	scheduler           *scheduler.Scheduler
	repeatInterval      time.Duration
	now                 func() time.Time
	handlers            map[string]commandHandler
	tasks               *task.FileStore
	focused             []task.Task
	pendingFocusPrompt  bool
	pendingFocusToggled map[int]bool
	pendingFocusAction  string
	sessionPath         string
	emoji               bool
	eventsPath          string
	tierLow             int
	tierMid             int
}

type commandHandler func(parts []string) commandResult

func newTimerCore(cfg config.Config, n notifier.Notifier) *timerCore {
	repeatInterval := time.Duration(cfg.RepeatSecs) * time.Second
	core := &timerCore{
		cycle: app.New(
			cfg.Pomodoro.WorkMinutes,
			cfg.Pomodoro.ShortBreakMinutes,
			cfg.Pomodoro.LongBreakMinutes,
			cfg.Pomodoro.LongBreakEvery,
			repeatInterval,
			n,
		),
		notifier:       n,
		state:          &reminderState{morningPending: cfg.MorningReminderPending},
		scheduler:      scheduler.New(cfg.Schedule.Days, cfg.Schedule.Time),
		repeatInterval: repeatInterval,
		now:            time.Now,
		emoji:          cfg.Emoji,
	}
	core.handlers = core.buildCommandHandlers()
	return core
}

func (d *timerCore) start(ctx context.Context) {
	startMorningScheduler(ctx, d.state, d.scheduler, d.repeatInterval, d.notifier)
	if d.state.isMorningPending() && d.cycle.State() == engine.Idle && d.scheduler.IsActiveNow(d.now()) {
		startMorningLoop(d.state, d.repeatInterval, d.notifier)
	}
}

func (d *timerCore) stop() {
	d.cycle.AdvanceDay(d.now())
	d.saveSession()
	d.state.stopMorningLoop()
}

func (d *timerCore) snapshot() (string, engine.State, bool) {
	d.cycle.AdvanceDay(d.now())
	return d.state.statusSnapshot(d.cycle)
}

func (d *timerCore) executeCommand(line string) commandResponse {
	d.cycle.AdvanceDay(d.now())
	result := d.execute(line)
	d.saveSession()
	statusLine, engineState, morningPending := d.snapshot()
	resp := commandResponse{
		StatusLine:     statusLine,
		EngineState:    engineState,
		MorningPending: morningPending,
		Message:        result.message,
		Exit:           result.exit,
		FocusLines:     d.formatFocusLines(),
	}
	if d.pendingFocusPrompt {
		resp.FocusPrompt = d.formatFocusPrompt()
	}
	if result.err != nil {
		resp.Error = result.err.Error()
	}
	return resp
}

type commandResult struct {
	message string
	exit    bool
	err     error
}

func (d *timerCore) execute(line string) commandResult {
	trimmed := strings.TrimSpace(line)
	if trimmed == "_cancel_focus" && d.pendingFocusPrompt {
		return d.cancelFocusPrompt()
	}
	if d.pendingFocusPrompt {
		return d.handleFocusPromptInput(trimmed)
	}
	if trimmed == "" {
		return commandResult{}
	}
	parts := strings.Fields(trimmed)
	handler, ok := d.handlers[parts[0]]
	if !ok {
		return commandResult{err: fmt.Errorf("unknown command: %s", parts[0])}
	}
	return handler(parts)
}

func (d *timerCore) buildCommandHandlers() map[string]commandHandler {
	return map[string]commandHandler{
		"start":      d.handleStart,
		"new-cycle":  d.handleNewCycle,
		"pause":      d.handlePause,
		"resume":     d.handleResume,
		"stop":       d.handleStop,
		"confirm":    d.handleConfirm,
		"snooze":     d.handleSnooze,
		"skip-today": d.handleSkipToday,
		"test-sound": d.handleTestSound,
		"status":     d.handleStatus,
		"stats":      d.handleStats,
		"quit":       d.handleQuit,
		"exit":       d.handleQuit,
		"task":       d.handleTask,
	}
}

func (d *timerCore) handleStart(_ []string) commandResult {
	d.state.stopMorningLoop()
	d.state.clearSnooze()
	if d.tasks != nil {
		return d.enterFocusPrompt("start")
	}
	d.cycle.Start()
	return commandResult{message: "Pomodoro started -- let's go!"}
}

func (d *timerCore) handleNewCycle(_ []string) commandResult {
	d.state.stopMorningLoop()
	d.state.clearSnooze()
	d.cycle.StartNewCycle()
	return commandResult{message: "New cycle started -- fresh start!"}
}

func (d *timerCore) handlePause(_ []string) commandResult {
	d.cycle.Pause()
	return commandResult{message: "Paused. Take your time."}
}

func (d *timerCore) handleResume(_ []string) commandResult {
	d.cycle.Resume()
	return commandResult{message: "Resumed -- back at it!"}
}

func (d *timerCore) handleStop(_ []string) commandResult {
	d.cycle.Stop()
	d.focused = nil
	return commandResult{message: "Stopped. Back to idle."}
}

func (d *timerCore) handleConfirm(_ []string) commandResult {
	d.cycle.Confirm()
	state := d.cycle.State()
	if state == engine.Work && d.tasks != nil && len(d.focused) == 0 {
		return d.enterFocusPrompt("confirm")
	}
	return commandResult{message: fmt.Sprintf("Confirmed -- %s", friendlyStateName(state))}
}

func (d *timerCore) handleSnooze(parts []string) commandResult {
	parsed, err := parseSnoozeDuration(parts)
	if err != nil {
		return commandResult{err: err}
	}
	if d.state.isMorningPending() {
		d.state.stopMorningLoop()
		d.state.setSnoozeUntil(d.now().Add(parsed))
		state := d.state
		repeatInterval := d.repeatInterval
		n := d.notifier
		cycle := d.cycle
		go func() {
			time.Sleep(parsed)
			if cycle.State() != engine.Idle {
				return
			}
			state.clearSnooze()
			startMorningLoop(state, repeatInterval, n)
		}()
		return commandResult{message: fmt.Sprintf("morning reminder snoozed for %s", parsed)}
	}
	d.cycle.Snooze(parsed)
	return commandResult{message: fmt.Sprintf("cycle reminder snoozed for %s", parsed)}
}

func (d *timerCore) handleSkipToday(_ []string) commandResult {
	d.state.stopMorningLoop()
	d.state.markSkippedToday(d.now())
	d.cycle.SkipToday()
	return commandResult{message: "Skipped reminders for today."}
}

func (d *timerCore) handleTestSound(_ []string) commandResult {
	if err := d.notifier.PlaySound("test"); err != nil {
		return commandResult{message: fmt.Sprintf("sound test failed: %v", err)}
	}
	return commandResult{message: "Sound test played."}
}

func (d *timerCore) handleStatus(_ []string) commandResult {
	return commandResult{}
}

func (d *timerCore) handleQuit(_ []string) commandResult {
	d.state.stopMorningLoop()
	return commandResult{message: "See you next time!", exit: true}
}

func parseSnoozeDuration(parts []string) (time.Duration, error) {
	if len(parts) < 2 {
		return 0, fmt.Errorf("usage: snooze <duration>")
	}
	raw := parts[1]
	if _, err := strconv.ParseFloat(raw, 64); err == nil {
		raw += "m"
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		return 0, fmt.Errorf("invalid duration: %v", err)
	}
	return d, nil
}

func startMorningLoop(state *reminderState, repeatInterval time.Duration, n notifier.Notifier) {
	ctx, shouldStart := state.beginMorningLoop()
	if !shouldStart {
		return
	}
	loop := reminder.New(repeatInterval, func() error {
		return n.PlaySound("morning")
	})
	go loop.Run(ctx)
}

func startMorningScheduler(ctx context.Context, state *reminderState, sched *scheduler.Scheduler, repeatInterval time.Duration, n notifier.Notifier) {
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

func (d *timerCore) saveSession() {
	if d.sessionPath == "" {
		return
	}
	var focusIDs []int
	for _, t := range d.focused {
		focusIDs = append(focusIDs, t.ID)
	}
	data := session.Data{
		SavedAt:        d.now(),
		App:            d.cycle.Snapshot(),
		FocusedTaskIDs: focusIDs,
	}
	if err := session.Save(d.sessionPath, data); err != nil {
		fmt.Fprintf(os.Stderr, "warning: session save failed: %v\n", err)
	}
}

func (d *timerCore) loadSession() error {
	if d.sessionPath == "" {
		return nil
	}
	data, err := session.Load(d.sessionPath)
	if err != nil {
		return err
	}
	if data.SavedAt.IsZero() {
		return nil
	}
	if !engine.IsSameDay(data.SavedAt, d.now()) {
		return nil
	}
	if err := d.cycle.Restore(data.App); err != nil {
		return err
	}
	if d.tasks != nil && len(data.FocusedTaskIDs) > 0 {
		activeByID := make(map[int]task.Task)
		for _, t := range d.tasks.Active() {
			activeByID[t.ID] = t
		}
		for _, id := range data.FocusedTaskIDs {
			if t, ok := activeByID[id]; ok {
				d.focused = append(d.focused, t)
			}
		}
	}
	d.cycle.AdvanceDay(d.now())
	if data.App.Engine.State != engine.Idle {
		d.state.markSkippedToday(d.now())
	}
	return nil
}

func commandsHelp() string {
	return strings.Join([]string{
		"commands:",
		"  start              start a pomodoro",
		"  new-cycle          start a fresh cycle",
		"  pause              pause the timer",
		"  resume             resume the timer",
		"  stop               stop and return to idle",
		"  confirm            continue to next phase",
		"  snooze <duration>  snooze reminder (e.g., snooze 10m)",
		"  skip-today         skip reminders for today",
		"  stats              show productivity dashboard",
		"  status             show current status",
		"  test-sound         test the reminder sound",
		"  quit               exit throwntom",
		"  exit               alias for quit",
		"",
		"task commands:",
		"  task add <desc>     add a task",
		"  task done <n>       complete a task",
		"  task remove <n>     delete a task",
		"  task list           show active tasks",
		"  task completed      show completed tasks",
		"  task clear          clear completed tasks",
		"  task focus <n>      focus on a task (work session)",
		"  task unfocus <n>    remove focus (work session)",
		"  task up <n>         move focused task up",
		"  task down <n>       move focused task down",
	}, "\n")
}
