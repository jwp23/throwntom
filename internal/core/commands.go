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
	errNotWorkSession   = errors.New("only available during a work session")
	errAlreadyFocused   = errors.New("is already focused")
)

// refusals are the sentinels for commands the current state does not allow;
// classifyError maps them to ErrorRefused.
var refusals = []error{errNotRunning, errNothingToSkip, errNothingToConfirm, errNotPaused, errNotWorkSession, errAlreadyFocused, errNoReminder}

func (c *Core) buildCommandHandlers() map[string]commandHandler {
	return map[string]commandHandler{
		"start":      c.handleStart,
		"new-cycle":  c.handleNewCycle,
		"pause":      c.handlePause,
		"resume":     c.handleResume,
		"stop":       c.handleStop,
		"skip":       c.handleSkip,
		"confirm":    c.handleConfirm,
		"snooze":     c.handleSnooze,
		"skip-today": c.handleSkipToday,
		"test-sound": c.handleTestSound,
		"status":     c.handleStatus,
		"stats":      c.handleStats,
		"quit":       c.handleQuit,
		"exit":       c.handleQuit,
		"task":       c.handleTask,
	}
}

func (c *Core) handleStart(_ []string) commandResult {
	c.reminder.cancel()
	// The focus prompt asks which tasks this pomodoro is for, so it belongs
	// only to a start that actually begins work — not to one resuming a break
	// a stop left owed.
	if c.tasks != nil && c.timer.OwedPhase() == engine.Work {
		return c.enterFocusPrompt("start")
	}
	c.timer.Start()
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

func (c *Core) handleNewCycle(_ []string) commandResult {
	c.timer.StartNewCycle()
	c.logEvent("pomodoro_started", nil)
	return commandResult{message: "New cycle started -- fresh start!"}
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
	before := c.timer.Snapshot().Engine
	// The phase the cycle is holding at was finished, and stop keeps it owed
	// rather than confirming it. Nothing else logs that completion — confirm
	// does, and a resuming start goes straight into the next phase — so
	// without this the pomodoro counts in the engine and is missing from the
	// stats, which is precisely the dangling-event defect stop was fixed for.
	if before.State == engine.AwaitingConfirm && !before.Skipped {
		c.logConfirmCompletion(before.LastPhase)
	}
	c.timer.Stop()
	if before.State != engine.Idle {
		c.logEvent("stopped", nil)
	}
	return commandResult{message: "Stopped. Start again when you're ready."}
}

// handleSkip moves the cycle on early. The skipped phase is not credited, so
// the event is a skip rather than a completion.
func (c *Core) handleSkip(_ []string) commandResult {
	skipped, ok := c.timer.Skip()
	if !ok {
		return commandResult{err: errNothingToSkip}
	}
	c.logEvent("skipped", map[string]any{"phase": skipped.String()})
	next, _, _ := c.nextStageLocked()
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
		c.logConfirmCompletion(snap.Engine.LastPhase)
	}
	c.timer.Confirm()
	state := c.timer.State()
	c.logPhaseStart(state)
	if state == engine.Work && c.tasks != nil && len(c.focused) == 0 {
		return c.enterFocusPrompt("confirm")
	}
	return commandResult{message: fmt.Sprintf("Confirmed -- %s", FriendlyStateName(state))}
}

func (c *Core) logConfirmCompletion(lastPhase engine.State) {
	switch lastPhase {
	case engine.Work:
		c.logEvent("pomodoro_completed", nil)
	case engine.ShortBreak:
		c.logEvent("break_completed", map[string]any{"kind": "short"})
	case engine.LongBreak:
		c.logEvent("break_completed", map[string]any{"kind": "long"})
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
	}
}

func (c *Core) handleSnooze(parts []string) commandResult {
	parsed, err := parseSnoozeDuration(parts)
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

func (c *Core) handleSkipToday(_ []string) commandResult {
	c.reminder.skipToday(c.now())
	c.timer.SkipToday()
	c.logEvent("skipped_today", nil)
	return commandResult{message: "Skipped reminders for today."}
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
	if d <= 0 {
		return 0, fmt.Errorf("snooze duration must be positive")
	}
	return d, nil
}

func Help() string {
	return strings.Join([]string{
		"commands:",
		"  start              start a pomodoro",
		"  new-cycle          start a fresh cycle",
		"  pause              pause the timer",
		"  resume             resume the timer",
		"  stop               suspend the cycle; start again to resume the owed phase",
		"  skip               end this phase now and move to the next stage",
		"  confirm            continue to next phase now",
		"  snooze <duration>  keep the owed phase and focused tasks, ask again later (e.g., snooze 10m)",
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
