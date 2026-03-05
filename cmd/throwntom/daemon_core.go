package main

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/jwp23/throwntom/internal/app"
	"github.com/jwp23/throwntom/internal/config"
	"github.com/jwp23/throwntom/internal/notifier"
	"github.com/jwp23/throwntom/internal/reminder"
	"github.com/jwp23/throwntom/internal/scheduler"
	"github.com/jwp23/throwntom/internal/task"
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
	if s.morningCancel != nil {
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
	handlers       map[string]daemonCommandHandler
	tasks          *task.FileStore
}

type daemonCommandHandler func(parts []string) daemonCommandResult

func newDaemonCore(cfg config.Config, n notifier.Notifier) *daemonCore {
	repeatInterval := time.Duration(cfg.RepeatSecs) * time.Second
	core := &daemonCore{
		cycle: app.New(
			cfg.WorkMinutes,
			cfg.ShortBreakMinutes,
			cfg.LongBreakMinutes,
			cfg.LongBreakEvery,
			repeatInterval,
			n,
		),
		notifier:       n,
		state:          &daemonState{morningPending: cfg.MorningReminderPending},
		scheduler:      scheduler.New(cfg.Schedule.Days, cfg.Schedule.Time),
		repeatInterval: repeatInterval,
		now:            time.Now,
	}
	core.handlers = core.buildCommandHandlers()
	return core
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
	handler, ok := d.handlers[parts[0]]
	if !ok {
		return daemonCommandResult{err: fmt.Errorf("unknown command: %s", parts[0])}
	}
	return handler(parts)
}

func (d *daemonCore) buildCommandHandlers() map[string]daemonCommandHandler {
	return map[string]daemonCommandHandler{
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
		"quit":       d.handleQuit,
		"exit":       d.handleQuit,
		"task":       d.handleTask,
	}
}

func (d *daemonCore) handleStart(_ []string) daemonCommandResult {
	d.state.stopMorningLoop()
	d.state.clearSnooze()
	d.cycle.Start()
	return daemonCommandResult{message: "pomodoro started"}
}

func (d *daemonCore) handleNewCycle(_ []string) daemonCommandResult {
	d.state.stopMorningLoop()
	d.state.clearSnooze()
	d.cycle.StartNewCycle()
	return daemonCommandResult{message: "new pomodoro cycle started"}
}

func (d *daemonCore) handlePause(_ []string) daemonCommandResult {
	d.cycle.Pause()
	return daemonCommandResult{message: "paused"}
}

func (d *daemonCore) handleResume(_ []string) daemonCommandResult {
	d.cycle.Resume()
	return daemonCommandResult{message: "resumed"}
}

func (d *daemonCore) handleStop(_ []string) daemonCommandResult {
	d.cycle.Stop()
	return daemonCommandResult{message: "stopped and returned to idle"}
}

func (d *daemonCore) handleConfirm(_ []string) daemonCommandResult {
	d.cycle.Confirm()
	return daemonCommandResult{message: fmt.Sprintf("confirmed, state=%s", d.cycle.Status())}
}

func (d *daemonCore) handleSnooze(parts []string) daemonCommandResult {
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
}

func (d *daemonCore) handleSkipToday(_ []string) daemonCommandResult {
	d.state.stopMorningLoop()
	d.state.markSkippedToday(d.now())
	d.cycle.SkipToday()
	return daemonCommandResult{message: "skipped reminders for today"}
}

func (d *daemonCore) handleTestSound(_ []string) daemonCommandResult {
	if err := d.notifier.PlaySound("test"); err != nil {
		return daemonCommandResult{message: fmt.Sprintf("sound test failed: %v", err)}
	}
	return daemonCommandResult{message: "sound test played"}
}

func (d *daemonCore) handleStatus(_ []string) daemonCommandResult {
	return daemonCommandResult{}
}

func (d *daemonCore) handleQuit(_ []string) daemonCommandResult {
	d.state.stopMorningLoop()
	return daemonCommandResult{message: "bye", exit: true}
}

func (d *daemonCore) handleTask(parts []string) daemonCommandResult {
	if d.tasks == nil {
		return daemonCommandResult{err: fmt.Errorf("task store not initialized")}
	}
	if len(parts) < 2 {
		return daemonCommandResult{err: fmt.Errorf("usage: task <subcommand>")}
	}
	switch parts[1] {
	case "add":
		return d.handleTaskAdd(parts)
	case "done":
		return d.handleTaskDone(parts)
	case "remove":
		return d.handleTaskRemove(parts)
	case "list":
		return d.handleTaskList()
	case "completed":
		return d.handleTaskCompleted()
	case "clear":
		return d.handleTaskClear()
	default:
		return daemonCommandResult{err: fmt.Errorf("unknown task subcommand: %s", parts[1])}
	}
}

func (d *daemonCore) handleTaskAdd(parts []string) daemonCommandResult {
	if len(parts) < 3 {
		return daemonCommandResult{err: fmt.Errorf("usage: task add <description>")}
	}
	desc := strings.Join(parts[2:], " ")
	t, err := d.tasks.Add(desc)
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("add task: %w", err)}
	}
	return daemonCommandResult{message: fmt.Sprintf("added task %d: %s", t.ID, t.Description)}
}

func (d *daemonCore) handleTaskDone(parts []string) daemonCommandResult {
	if len(parts) < 3 {
		return daemonCommandResult{err: fmt.Errorf("usage: task done <n>")}
	}
	pos, err := strconv.Atoi(parts[2])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid task number: %s", parts[2])}
	}
	id, err := d.tasks.ActiveTaskID(pos)
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("task done: %w", err)}
	}
	if err := d.tasks.Complete(id); err != nil {
		return daemonCommandResult{err: fmt.Errorf("task done: %w", err)}
	}
	return daemonCommandResult{message: fmt.Sprintf("task %d completed", pos)}
}

func (d *daemonCore) handleTaskRemove(parts []string) daemonCommandResult {
	if len(parts) < 3 {
		return daemonCommandResult{err: fmt.Errorf("usage: task remove <n>")}
	}
	pos, err := strconv.Atoi(parts[2])
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("invalid task number: %s", parts[2])}
	}
	id, err := d.tasks.ActiveTaskID(pos)
	if err != nil {
		return daemonCommandResult{err: fmt.Errorf("task remove: %w", err)}
	}
	if err := d.tasks.Remove(id); err != nil {
		return daemonCommandResult{err: fmt.Errorf("task remove: %w", err)}
	}
	return daemonCommandResult{message: fmt.Sprintf("task %d removed", pos)}
}

func (d *daemonCore) handleTaskList() daemonCommandResult {
	active := d.tasks.Active()
	if len(active) == 0 {
		return daemonCommandResult{message: "no active tasks"}
	}
	var lines []string
	for i, t := range active {
		lines = append(lines, fmt.Sprintf("  %d) %s", i+1, t.Description))
	}
	return daemonCommandResult{message: strings.Join(lines, "\n")}
}

func (d *daemonCore) handleTaskCompleted() daemonCommandResult {
	done := d.tasks.Completed()
	if len(done) == 0 {
		return daemonCommandResult{message: "no completed tasks"}
	}
	var lines []string
	for _, t := range done {
		lines = append(lines, fmt.Sprintf("  [done] %s (%s)", t.Description, t.CompletedAt.Format("15:04")))
	}
	return daemonCommandResult{message: strings.Join(lines, "\n")}
}

func (d *daemonCore) handleTaskClear() daemonCommandResult {
	if err := d.tasks.ClearCompleted(); err != nil {
		return daemonCommandResult{err: fmt.Errorf("clear completed: %w", err)}
	}
	return daemonCommandResult{message: "completed tasks cleared"}
}

func (d *daemonCore) initTasks(path string) error {
	store, err := task.NewFileStore(path)
	if err != nil {
		return fmt.Errorf("init task store: %w", err)
	}
	d.tasks = store
	return nil
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
		"  new-cycle          start a fresh pomodoro cycle",
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
