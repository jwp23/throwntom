package core

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/jwp23/throwntom/v3/internal/analytics"
	"github.com/jwp23/throwntom/v3/internal/app"
	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/engine"
	"github.com/jwp23/throwntom/v3/internal/eventlog"
	"github.com/jwp23/throwntom/v3/internal/notifier"
	"github.com/jwp23/throwntom/v3/internal/scheduler"
	"github.com/jwp23/throwntom/v3/internal/task"
)

type Core struct {
	mu                  sync.Mutex
	publishMu           sync.Mutex
	subscribers         map[chan State]struct{}
	stopped             bool
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
	eventWriter         *eventlog.Writer
	eventsPath          string
	longBreakEvery      int
	// afterFinalPublish runs between Stop's final publish and the flag that
	// ends publishing. It is the seam a test uses to drive a publish into that
	// window; nothing in production sets it.
	afterFinalPublish func()
}

type commandHandler func(parts []string) commandResult

func newCore(cfg config.Config, n notifier.Notifier) *Core {
	repeatInterval := time.Duration(cfg.RepeatSecs) * time.Second
	c := &Core{
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
		scheduler:      scheduler.New(config.ScheduleDayTimes(cfg.Schedule)),
		repeatInterval: repeatInterval,
		now:            time.Now,
		longBreakEvery: cfg.Pomodoro.LongBreakEvery,
		subscribers:    make(map[chan State]struct{}),
	}
	c.handlers = c.buildCommandHandlers()
	c.cycle.SetOnChange(c.publishAsync)
	c.state.onChange = c.publishAsync
	return c
}

type Paths struct {
	Tasks   string
	Session string
	Events  string
	Socket  string
	Lock    string
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
	return Paths{Tasks: tasks, Session: sess, Events: events, Socket: socket, Lock: lock}, nil
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
	startMorningScheduler(ctx, c.state, c.scheduler, c.repeatInterval, c.notifier)
	if c.state.isMorningPending() && c.cycle.State() == engine.Idle && c.scheduler.IsActiveNow(c.now()) {
		startMorningLoop(c.state, c.repeatInterval, c.notifier)
	}
}

// Stop publishes a final state and then stops publishing: once it returns, no
// background change can save the session or reach a subscriber. Holding
// publishMu across the final publish and the stopped flag is what makes that
// true: every other publish takes publishMu first, so one already queued
// cannot slip between them.
func (c *Core) Stop() {
	c.mu.Lock()
	c.cycle.AdvanceDay(c.now())
	c.state.stopMorningLoop()
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
	c.cycle.AdvanceDay(c.now())
	return c.state.statusSnapshot(c.cycle)
}

func (c *Core) NextStage() (engine.State, time.Duration, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.nextStageLocked()
}

func (c *Core) nextStageLocked() (engine.State, time.Duration, bool) {
	if c.cycle.State() != engine.AwaitingConfirm {
		return engine.Idle, 0, false
	}
	next, duration := c.cycle.NextStage()
	return next, duration, true
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
	c.cycle.AdvanceDay(c.now())
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
		if c.cycle.State() == engine.AwaitingConfirm {
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
