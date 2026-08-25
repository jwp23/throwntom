package core

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

func (c *Core) buildCommandHandlers() map[string]commandHandler {
	return map[string]commandHandler{
		"start":      c.handleStart,
		"new-cycle":  c.handleNewCycle,
		"pause":      c.handlePause,
		"resume":     c.handleResume,
		"stop":       c.handleStop,
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
	c.state.stopMorningLoop()
	c.state.clearSnooze()
	if c.tasks != nil {
		return c.enterFocusPrompt("start")
	}
	c.cycle.Start()
	c.logEvent("pomodoro_started", nil)
	return commandResult{message: "Pomodoro started -- let's go!"}
}

func (c *Core) handleNewCycle(_ []string) commandResult {
	c.state.stopMorningLoop()
	c.state.clearSnooze()
	c.cycle.StartNewCycle()
	c.logEvent("pomodoro_started", nil)
	return commandResult{message: "New cycle started -- fresh start!"}
}

func (c *Core) handlePause(_ []string) commandResult {
	c.cycle.Pause()
	c.logEvent("paused", nil)
	return commandResult{message: "Paused. Take your time."}
}

func (c *Core) handleResume(_ []string) commandResult {
	c.cycle.Resume()
	c.logEvent("resumed", nil)
	return commandResult{message: "Resumed -- back at it!"}
}

func (c *Core) handleStop(_ []string) commandResult {
	c.cycle.Stop()
	c.focused = nil
	return commandResult{message: "Stopped. Back to idle."}
}

func (c *Core) handleConfirm(_ []string) commandResult {
	snap := c.cycle.Snapshot()
	c.logConfirmCompletion(snap.Engine.LastPhase)
	c.cycle.Confirm()
	state := c.cycle.State()
	c.logConfirmStart(state)
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

func (c *Core) logConfirmStart(newState engine.State) {
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
	snoozeSecs := int(parsed.Seconds())
	if c.state.isMorningPending() {
		c.state.stopMorningLoop()
		c.state.setSnoozeUntil(c.now().Add(parsed))
		state := c.state
		repeatInterval := c.repeatInterval
		n := c.notifier
		cycle := c.cycle
		go func() {
			time.Sleep(parsed)
			if cycle.State() != engine.Idle {
				return
			}
			state.clearSnooze()
			startMorningLoop(state, repeatInterval, n)
		}()
		c.logEvent("snoozed", map[string]any{"duration_secs": snoozeSecs})
		return commandResult{message: fmt.Sprintf("morning reminder snoozed for %s", parsed)}
	}
	c.cycle.Snooze(parsed)
	c.logEvent("snoozed", map[string]any{"duration_secs": snoozeSecs})
	return commandResult{message: fmt.Sprintf("cycle reminder snoozed for %s", parsed)}
}

func (c *Core) handleSkipToday(_ []string) commandResult {
	c.state.stopMorningLoop()
	c.state.markSkippedToday(c.now())
	c.cycle.SkipToday()
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
	c.state.stopMorningLoop()
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

func Help() string {
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
