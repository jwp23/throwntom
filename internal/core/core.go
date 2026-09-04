package core

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/jwp23/throwntom/v3/internal/analytics"
	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/eventlog"
	"github.com/jwp23/throwntom/v3/internal/notifier"
	"github.com/jwp23/throwntom/v3/internal/pomodoro"
	"github.com/jwp23/throwntom/v3/internal/reminder"
	"github.com/jwp23/throwntom/v3/internal/scheduler"
	"github.com/jwp23/throwntom/v3/internal/task"
)

type Core struct {
	mu                  sync.Mutex
	publishMu           sync.Mutex
	subscribers         map[chan State]struct{}
	stopped             bool
	timer               *pomodoro.Timer
	notifier            notifier.Notifier
	reminder            *outstandingReminder
	scheduler           *scheduler.Scheduler
	now                 func() time.Time
	handlers            map[string]commandHandler
	tasks               *task.FileStore
	focused             []task.Task
	pendingFocusPrompt  bool
	pendingFocusToggled map[int]bool
	pendingFocusAction  string
	sessionPath         string
	eventWriter         *eventlog.Writer
	eventsPath          string
	longBreakEvery      int
	// warnOut is where session warnings go. It defaults to os.Stderr; tests
	// point it at a buffer so they can assert on a warning's content instead
	// of letting it leak into the test run's own output.
	warnOut io.Writer
	// floatWindowWhenWaiting is carried for clients, not acted on here. See
	// the field of the same name on State.
	floatWindowWhenWaiting bool
	// bounceDockWhenPaused is carried for clients, not acted on here. See the
	// field of the same name on State.
	bounceDockWhenPaused bool
	// morningPending is the config's answer to whether today's morning
	// reminder is still owed at start-up.
	morningPending bool
	// started guards against a second Start: Start is meant to run once per
	// process, and a second call would replace stopSchedule and scheduleDone
	// out from under the first schedule goroutine, orphaning it since Stop
	// would then wait on the replacement's done channel instead. A repeat
	// call is a programming error, so Start panics on it instead of silently
	// corrupting the schedule.
	started bool
	// stopSchedule ends the schedule tick started by Start; Stop calls it and
	// waits on scheduleDone so no tick can run after Stop returns, regardless
	// of whether the caller's ctx has been cancelled.
	stopSchedule context.CancelFunc
	scheduleDone chan struct{}
	// afterFinalPublish runs between Stop's final publish and the flag that
	// ends publishing. It is the seam a test uses to drive a publish into that
	// window; nothing in production sets it.
	afterFinalPublish func()
}

type commandHandler func(parts []string) commandResult

func newCore(cfg config.Config, n notifier.Notifier) *Core {
	policy := reminder.NewPolicy(
		time.Duration(cfg.RepeatSecs)*time.Second,
		time.Duration(cfg.RepeatLimitSecs)*time.Second,
	)
	c := &Core{
		timer: pomodoro.New(
			cfg.Pomodoro.WorkMinutes,
			cfg.Pomodoro.ShortBreakMinutes,
			cfg.Pomodoro.LongBreakMinutes,
			cfg.Pomodoro.LongBreakEvery,
		),
		notifier:               n,
		reminder:               newOutstandingReminder(policy, n),
		scheduler:              scheduler.New(config.ScheduleDayTimes(cfg.Schedule)),
		now:                    time.Now,
		morningPending:         cfg.MorningReminderPending,
		longBreakEvery:         cfg.Pomodoro.LongBreakEvery,
		floatWindowWhenWaiting: cfg.FloatWindowWhenWaiting,
		bounceDockWhenPaused:   cfg.BounceDockWhenPaused,
		subscribers:            make(map[chan State]struct{}),
		warnOut:                os.Stderr,
	}
	c.timer.SetPausedTooLongAfter(pausedTooLongAfter(cfg))
	c.handlers = c.buildCommandHandlers()
	c.timer.SetOnChange(c.publishAsync)
	c.timer.SetOnTransition(c.onTransition)
	c.reminder.onChange = c.publishAsync
	return c
}

// onTransition runs inside the timer's lock on every change of engine state.
// awaiting_confirm is the one state that owes a reminder; leaving any state
// answers whichever reminder was outstanding, morning included.
func (c *Core) onTransition(to engine.State) {
	if to == engine.AwaitingConfirm {
		c.reminder.raise(reminderCycle)
		return
	}
	c.reminder.cancel()
}

type Paths struct {
	Tasks   string
	Session string
	Events  string
	Socket  string
	Lock    string
	Config  string
}

func DefaultPaths() (Paths, error) {
	tasks, err := config.DirPath("tasks.json")
	if err != nil {
		return Paths{}, err
	}
	sess, err := config.DirPath("session.json")
	if err != nil {
		return Paths{}, err
	}
	events, err := config.DirPath("events.jsonl")
	if err != nil {
		return Paths{}, err
	}
	socket, err := config.DirPath("daemon.sock")
	if err != nil {
		return Paths{}, err
	}
	lock, err := config.DirPath("daemon.lock")
	if err != nil {
		return Paths{}, err
	}
	cfgPath, err := config.DirPath("config.toml")
	if err != nil {
		return Paths{}, err
	}
	return Paths{Tasks: tasks, Session: sess, Events: events, Socket: socket, Lock: lock, Config: cfgPath}, nil
}

func New(cfg config.Config, n notifier.Notifier, paths Paths) (*Core, error) {
	c := newCore(cfg, n)
	if err := c.initTasks(paths.Tasks); err != nil {
		return nil, err
	}
	c.sessionPath = paths.Session
	if err := c.loadSession(); err != nil {
		fmt.Fprintf(os.Stderr, "warning: could not load session: %v\n", err)
	}
	c.eventWriter = eventlog.NewWriter(paths.Events)
	c.eventsPath = paths.Events
	return c, nil
}

func (c *Core) Start(ctx context.Context) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.started {
		panic("core: Start called more than once")
	}
	c.started = true
	scheduleCtx, cancel := context.WithCancel(ctx)
	c.stopSchedule = cancel
	done := make(chan struct{})
	c.scheduleDone = done
	go func() {
		defer close(done)
		c.runMorningSchedule(scheduleCtx)
	}()
	// A daemon starting up mid-morning rings for the reminder it was not
	// running to give, so it asks whether the schedule has already struck
	// today rather than whether it is striking now. What it must not do is
	// ring for a morning the day has already answered: morningPending is the
	// config's standing default, and only the reminder knows what today did.
	now := c.now()
	if c.morningPending && c.timer.State() == engine.Idle &&
		c.reminder.shouldRaiseMorning(now, c.scheduler.IsActiveNow(now)) {
		c.reminder.raise(reminderMorning)
	}
}

// Stop publishes a final state and then stops publishing: once it returns, no
// background change can save the session or reach a subscriber. Holding
// publishMu across the final publish and the stopped flag is what makes that
// true: every other publish takes publishMu first, so one already queued
// cannot slip between them.
func (c *Core) Stop() {
	// Stop the schedule tick and wait for it to exit before taking c.mu:
	// tickMorning takes c.mu itself, so waiting first (rather than while
	// holding the lock) lets an in-flight tick finish instead of deadlocking.
	c.mu.Lock()
	stopSchedule, scheduleDone := c.stopSchedule, c.scheduleDone
	c.mu.Unlock()
	if stopSchedule != nil {
		stopSchedule()
		<-scheduleDone
	}

	c.mu.Lock()
	c.timer.AdvanceDay(c.now())
	c.reminder.cancel()
	c.mu.Unlock()

	c.publishMu.Lock()
	defer c.publishMu.Unlock()
	c.saveAndFanOut()
	if c.afterFinalPublish != nil {
		c.afterFinalPublish()
	}
	c.mu.Lock()
	c.stopped = true
	c.mu.Unlock()
}

func (c *Core) Status() (statusLine string, state engine.State, morningPending bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.statusLocked()
}

func (c *Core) statusLocked() (statusLine string, state engine.State, morningPending bool) {
	c.timer.AdvanceDay(c.now())
	return c.timer.StatusLine(), c.timer.State(), c.reminder.outstanding() == reminderMorning
}

// PlaysSound reports whether this core's notifier makes a sound. The notifier
// is chosen by the composition root and fixed for the core's life, so a caller
// that has to say what sound this process will produce asks rather than
// assuming which notifier it was given.
func (c *Core) PlaysSound() bool {
	return notifier.Audible(c.notifier)
}

func (c *Core) NextStage() (engine.State, time.Duration, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.nextStageLocked()
}

func (c *Core) nextStageLocked() (engine.State, time.Duration, bool) {
	if c.timer.State() != engine.AwaitingConfirm {
		return engine.Idle, 0, false
	}
	next, duration := c.timer.NextStage()
	return next, duration, true
}

// owedStageLocked reports the phase a start would enter and how long it would
// run. Only an idle timer owes anything: a running or paused phase has nothing
// to resume, and at awaiting-confirm the phase start would enter is the one
// NextStage already names.
func (c *Core) owedStageLocked() (engine.State, time.Duration, bool) {
	if c.timer.State() != engine.Idle {
		return engine.Idle, 0, false
	}
	owed, duration := c.timer.OwedStage()
	return owed, duration, true
}

// ErrorKind tells a caller why a command failed: a malformed request or a
// valid command the current state refuses.
type ErrorKind int

const (
	ErrorNone ErrorKind = iota
	// ErrorUsage is an unknown command, a missing or unparseable argument or
	// an out-of-range position.
	ErrorUsage
	// ErrorRefused is a well-formed command the current state does not allow.
	ErrorRefused
)

type Response struct {
	StatusLine     string
	EngineState    engine.State
	MorningPending bool
	Message        string
	Error          string
	ErrorKind      ErrorKind
	Exit           bool
	Focused        []task.Task
	FocusPrompt    string
	Stats          *analytics.Dashboard
}

func (c *Core) Execute(line string) Response {
	c.mu.Lock()
	c.timer.AdvanceDay(c.now())
	result := c.executeLocked(line)
	resp := c.responseLocked(result)
	c.mu.Unlock()
	c.publish()
	return resp
}

func (c *Core) CancelFocus() Response {
	c.mu.Lock()
	result := c.cancelFocusPrompt()
	resp := c.responseLocked(result)
	c.mu.Unlock()
	c.publish()
	return resp
}

func (c *Core) responseLocked(result commandResult) Response {
	statusLine, engineState, morningPending := c.statusLocked()
	resp := Response{
		StatusLine:     statusLine,
		EngineState:    engineState,
		MorningPending: morningPending,
		Message:        result.message,
		Exit:           result.exit,
		Focused:        c.focusedLocked(),
		Stats:          result.stats,
	}
	if c.pendingFocusPrompt {
		resp.FocusPrompt = c.focusPromptLocked()
	}
	if result.err != nil {
		resp.Error = result.err.Error()
		resp.ErrorKind = classifyError(result.err)
	}
	return resp
}

// classifyError separates state refusals, which the sentinels in commands.go
// and tasks.go mark, from everything else: malformed input.
func classifyError(err error) ErrorKind {
	for _, refusal := range refusals {
		if errors.Is(err, refusal) {
			return ErrorRefused
		}
	}
	return ErrorUsage
}

type commandResult struct {
	message string
	stats   *analytics.Dashboard
	exit    bool
	err     error
}

// executeLocked runs one command. Callers must hold c.mu: every handler reads
// or mutates Core state.
func (c *Core) executeLocked(line string) commandResult {
	trimmed := strings.TrimSpace(line)
	if c.pendingFocusPrompt {
		return c.handleFocusPromptInput(trimmed)
	}
	if trimmed == "" {
		if c.timer.State() == engine.AwaitingConfirm {
			return c.handleConfirm(nil)
		}
		return commandResult{}
	}
	parts := strings.Fields(trimmed)
	handler, ok := c.handlers[parts[0]]
	if !ok {
		return commandResult{err: fmt.Errorf("unknown command: %s", parts[0])}
	}
	return handler(parts)
}

func (c *Core) logEvent(eventType string, data map[string]any) {
	if c.eventWriter == nil {
		return
	}
	if err := c.eventWriter.Log(eventType, data); err != nil {
		fmt.Fprintf(os.Stderr, "warning: event log: %v\n", err)
	}
}

func FriendlyStateName(state engine.State) string {
	switch state {
	case engine.Work:
		return "pomodoro"
	case engine.ShortBreak:
		return "short break"
	case engine.LongBreak:
		return "long break"
	case engine.Idle:
		return "idle"
	case engine.Paused:
		return "paused"
	case engine.AwaitingConfirm:
		return "awaiting confirmation"
	default:
		return state.String()
	}
}
