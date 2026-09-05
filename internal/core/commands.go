package core

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

var (
	errNotRunning       = errors.New("nothing to pause: timer is not running")
	errNothingToSkip    = errors.New("nothing to skip: timer is not running")
	errNothingToConfirm = errors.New("nothing to confirm: no phase is waiting")
	errNotPaused        = errors.New("nothing to resume: timer is not paused")
	errAlreadyFocused   = errors.New("is already focused")
)

// refusals are the sentinels for commands the current state does not allow;
// classifyError maps them to ErrorRefused.
var refusals = []error{errNotRunning, errNothingToSkip, errNothingToConfirm, errNotPaused, errAlreadyFocused, errNoReminder, errNoSnooze}

func (c *Core) buildCommandHandlers() map[string]commandHandler {
	return map[string]commandHandler{
		"start":      c.handleStart,
		"new-cycle":  c.handleNewCycle,
		"lunch":      c.handleLunch,
		"meeting":    c.handleMeeting,
		"pause":      c.handlePause,
		"resume":     c.handleResume,
		"stop":       c.handleStop,
		"skip":       c.handleSkip,
		"confirm":    c.handleConfirm,
		"snooze":     c.handleSnooze,
		"unsnooze":   c.handleUnsnooze,
		"skip-today": c.handleSkipToday,
		"test-sound": c.handleTestSound,
		"status":     c.handleStatus,
		"stats":      c.handleStats,
		"quit":       c.handleQuit,
		"exit":       c.handleQuit,
		"task":       c.handleTask,
	}
}

// handleStart picks the cycle up. A phase waiting to be confirmed has already
// been earned, so start at that boundary means confirm: stop is a suspend and
// the break it leaves owed survives it, and start must not be the one verb
// that throws the same break — and the completion behind it — away.
func (c *Core) handleStart(parts []string) commandResult {
	if c.timer.State() == engine.AwaitingConfirm {
		return c.handleConfirm(parts)
	}
	c.reminder.cancel()
	// The focus prompt asks which tasks this pomodoro is for, so it belongs
	// only to a start that actually begins work — not to one resuming a break
	// a stop left owed, and not to one aimed at a cycle that is already under
	// way. Only an idle timer owes anything, which is why the question goes
	// through owedStageLocked rather than the engine's raw owed phase: that
	// reports Work for any non-idle state, so asking it directly opened the
	// prompt on a start issued while paused or mid-phase.
	if owed, _, ok := c.owedStageLocked(); ok && c.tasks != nil && owed == engine.Work {
		return c.enterFocusPrompt("start")
	}
	before := c.timer.Start()
	c.logDisplacedCompletion(before)
	state := c.timer.State()
	c.logPhaseStart(state)
	return commandResult{message: startedMessage(state)}
}

// startedMessage announces the phase a start entered, which after a stop may
// be the break that stop left owed rather than a pomodoro.
func startedMessage(state engine.State) string {
	if state == engine.Work {
		return "Pomodoro started -- let's go!"
	}
	return fmt.Sprintf("Back to your %s.", FriendlyStateName(state))
}

// handleNewCycle abandons the cycle and begins a fresh one. A phase that was
// waiting to be confirmed is still credited on the way past: the engine
// counted it the moment it finished, and a new cycle is the user discarding
// what comes next, not what they already did.
func (c *Core) handleNewCycle(_ []string) commandResult {
	before := c.timer.StartNewCycle()
	c.logDisplacedCompletion(before)
	c.logEvent("pomodoro_started", nil)
	return commandResult{message: "New cycle started -- fresh start!"}
}

// handleLunch takes the user to lunch, whatever the timer was doing. Lunch is
// the one break nothing earns and no schedule picks, so it needs no state to
// be in and refuses nothing. A phase that was waiting to be confirmed is still
// credited on the way past, for the reason new-cycle credits it: the engine
// counted it the moment it finished.
func (c *Core) handleLunch(_ []string) commandResult {
	before := c.timer.StartLunch()
	c.logDisplacedCompletion(before)
	c.logPhaseStart(engine.Lunch)
	return commandResult{message: "Lunch started -- a fresh block when you're back."}
}

// handleMeeting takes the user into a meeting of the length they name. Like
// lunch it needs no state to be in and refuses nothing but a length it cannot
// read, and a phase waiting to be confirmed is still credited on the way past.
//
// Unlike lunch it is worked time: the block it interrupts is still the block
// it returns to, and the time spent is credited as pomodoros when it ends.
func (c *Core) handleMeeting(parts []string) commandResult {
	parsed, err := parseDurationArg(parts, "meeting")
	if err != nil {
		return commandResult{err: err}
	}
	if parsed > 24*time.Hour {
		return commandResult{err: errors.New("meeting duration must be one day or less")}
	}
	before := c.timer.StartMeeting(parsed)
	c.logDisplacedCompletion(before)
	return commandResult{message: fmt.Sprintf("Meeting started -- %s. It counts toward your day.", parsed)}
}

func (c *Core) handlePause(_ []string) commandResult {
	if !c.timer.Pause() {
		return commandResult{err: errNotRunning}
	}
	c.logEvent("paused", nil)
	return commandResult{message: "Paused. Take your time."}
}

func (c *Core) handleResume(_ []string) commandResult {
	if !c.timer.Resume() {
		return commandResult{err: errNotPaused}
	}
	c.logEvent("resumed", nil)
	return commandResult{message: "Resumed -- back at it!"}
}

// handleStop suspends the cycle. Stop is not an abandon: the phase the cycle
// owes and the tasks in focus both survive it, so a later start picks up where
// this left off. The event it logs is what terminates the pomodoro already
// open in the log.
func (c *Core) handleStop(_ []string) commandResult {
	// Stop reports the state as of when it actually stopped rather than a
	// state fetched separately beforehand: the phase deadline runs on its
	// own goroutine and could otherwise complete the phase in the gap
	// between a Snapshot call here and Stop itself, leaving this stale.
	before := c.timer.Stop()
	c.logDisplacedCompletion(before)
	if before.State != engine.Idle {
		c.logEvent("stopped", nil)
	}
	return commandResult{message: "Stopped. Start again when you're ready."}
}

// handleSkip moves the cycle on early. The skipped phase is not credited, so
// the event is a skip rather than a completion.
//
// A meeting is the exception, and it is not really a skip at all: the time
// spent in it is credited, so the phase reaches the same boundary having
// earned something. Its completion is logged where every other completion is,
// at the confirm that follows, and calling it skipped here would both record a
// discard that did not happen and tell the user their meeting was thrown away.
func (c *Core) handleSkip(_ []string) commandResult {
	ended, ok := c.timer.Skip()
	if !ok {
		return commandResult{err: errNothingToSkip}
	}
	next, _, _ := c.nextStageLocked()
	if ended == engine.Meeting {
		return commandResult{message: fmt.Sprintf("Meeting ended -- %s next", FriendlyStateName(next))}
	}
	c.logEvent("skipped", map[string]any{"phase": ended.String()})
	return commandResult{message: fmt.Sprintf("Skipped -- %s next", FriendlyStateName(next))}
}

// handleConfirm advances the phase waiting on the user. It refuses when none
// is: confirm records the completion of the phase in lastPhase, and lastPhase
// outlives the state that earned it — a stop keeps it owed, and the engine
// keeps it while the next phase runs — so an unguarded confirm would log that
// same completion again every time it was called.
func (c *Core) handleConfirm(_ []string) commandResult {
	snap := c.timer.Snapshot()
	if snap.Engine.State != engine.AwaitingConfirm {
		return commandResult{err: errNothingToConfirm}
	}
	if !snap.Engine.Skipped {
		c.logConfirmCompletion(snap.Engine)
	}
	c.timer.Confirm()
	state := c.timer.State()
	c.logPhaseStart(state)
	if state == engine.Work && c.tasks != nil && len(c.focused) == 0 {
		return c.enterFocusPrompt("confirm")
	}
	return commandResult{message: fmt.Sprintf("Confirmed -- %s", FriendlyStateName(state))}
}

// logDisplacedCompletion credits a phase that was waiting to be confirmed when
// a verb other than confirm moved the cycle past it. Only confirm logs a
// completion, so without this the engine counts a pomodoro the event log never
// sees and the dashboard silently loses it. A skipped phase was never earned
// and is credited to nobody.
func (c *Core) logDisplacedCompletion(before engine.Snapshot) {
	if before.State == engine.AwaitingConfirm && !before.Skipped {
		c.logConfirmCompletion(before)
	}
}

func (c *Core) logConfirmCompletion(snap engine.Snapshot) {
	switch snap.LastPhase {
	case engine.Work:
		c.logEvent("pomodoro_completed", nil)
	// A meeting is neither a pomodoro nor a break: one event carries the whole
	// credit its length earned, so the log says a meeting happened rather than
	// claiming pomodoros nobody sat.
	case engine.Meeting:
		c.logEvent("meeting_completed", map[string]any{
			"pomodoros": snap.LastCredit,
			"minutes":   snap.LastMeetingMinutes,
		})
	case engine.ShortBreak:
		c.logEvent("break_completed", map[string]any{"kind": "short"})
	case engine.LongBreak:
		c.logEvent("break_completed", map[string]any{"kind": "long"})
	case engine.Lunch:
		c.logEvent("break_completed", map[string]any{"kind": "lunch"})
	}
}

// logPhaseStart records the phase the timer has just entered, whether it was
// reached by confirming the previous one or by starting after a stop.
func (c *Core) logPhaseStart(newState engine.State) {
	switch newState {
	case engine.Work:
		c.logEvent("pomodoro_started", nil)
	case engine.ShortBreak:
		c.logEvent("break_started", map[string]any{"kind": "short"})
	case engine.LongBreak:
		c.logEvent("break_started", map[string]any{"kind": "long"})
	case engine.Lunch:
		c.logEvent("break_started", map[string]any{"kind": "lunch"})
	}
}

func (c *Core) handleSnooze(parts []string) commandResult {
	parsed, err := parseDurationArg(parts, "snooze")
	if err != nil {
		return commandResult{err: err}
	}
	kind, err := c.reminder.suppress(c.now().Add(parsed))
	if err != nil {
		return commandResult{err: err}
	}
	c.logEvent("snoozed", map[string]any{"duration_secs": int(parsed.Seconds())})
	return commandResult{message: fmt.Sprintf("%s reminder snoozed for %s", kind.label(), parsed)}
}

// handleUnsnooze ends a snooze early. It is the inverse of snooze and nothing
// more: the nudge comes straight back, where start and skip-today reach the
// same deadline by retiring the reminder outright.
func (c *Core) handleUnsnooze(_ []string) commandResult {
	kind, err := c.reminder.unsuppress()
	if err != nil {
		return commandResult{err: err}
	}
	c.logEvent("unsnoozed", nil)
	return commandResult{message: fmt.Sprintf("%s reminder is back", kind.label())}
}

func (c *Core) handleSkipToday(_ []string) commandResult {
	c.reminder.skipToday(c.now())
	c.timer.SkipToday()
	c.logEvent("skipped_today", nil)
	return commandResult{message: "Done for today -- no more reminders until tomorrow."}
}

func (c *Core) handleTestSound(_ []string) commandResult {
	if err := c.notifier.PlaySound("test"); err != nil {
		return commandResult{message: fmt.Sprintf("sound test failed: %v", err)}
	}
	return commandResult{message: "Sound test played."}
}

func (c *Core) handleStatus(_ []string) commandResult {
	return commandResult{}
}

func (c *Core) handleQuit(_ []string) commandResult {
	c.reminder.cancel()
	return commandResult{message: "See you next time!", exit: true}
}

// parseDurationArg reads the duration a verb was given. A bare number means
// minutes, which is how a duration is spoken about here; anything else is read
// the way Go reads a duration. The verb names itself in every message so a
// refusal says which command was refused.
func parseDurationArg(parts []string, verb string) (time.Duration, error) {
	if len(parts) < 2 {
		return 0, fmt.Errorf("usage: %s <duration>", verb)
	}
	raw := parts[1]
	if _, err := strconv.ParseFloat(raw, 64); err == nil {
		raw += "m"
	}
	d, err := time.ParseDuration(raw)
	if err != nil {
		return 0, fmt.Errorf("invalid duration: %v", err)
	}
	if d <= 0 {
		return 0, fmt.Errorf("%s duration must be positive", verb)
	}
	return d, nil
}

func Help() string {
	return strings.Join([]string{
		"commands:",
		"  start              start a pomodoro, or take the phase you are owed",
		"  new-cycle          start a fresh cycle",
		"  lunch              take the lunch break; the pomodoro after it starts a fresh block",
		"  meeting <duration> attend a meeting; its time counts as pomodoros (e.g., meeting 30)",
		"  pause              pause the timer",
		"  resume             resume the timer",
		"  stop               suspend the cycle; start again to resume the owed phase",
		"  skip               end this phase now and move to the next stage",
		"  confirm            continue to next phase now",
		"  snooze <duration>  keep the owed phase and focused tasks, ask again later (e.g., snooze 10m)",
		"  unsnooze           end a snooze now and bring the reminder back",
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
		"  task focus <n>      focus on a task",
		"  task unfocus <n>    remove focus",
		"  task up <n>         move focused task up",
		"  task down <n>       move focused task down",
	}, "\n")
}
