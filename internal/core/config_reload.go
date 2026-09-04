package core

import (
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/reminder"
	"github.com/jwp23/throwntom/v3/internal/scheduler"
)

// ApplyConfig puts a reloaded config in force at once, in-flight phase
// included: ADR-006 (3). Phase durations, the cycle length, the schedule and
// the reminder policy all take effect without a restart. Two things do not,
// each for a reason named where it is settled: morning_reminder_pending
// below, and sound_command, which the client builds its notifier from before
// the core exists.
func (c *Core) ApplyConfig(cfg config.Config) {
	c.mu.Lock()
	// A stopped core takes no more config. Without this, a reload arriving
	// after Stop could arm a phase timer that outlives the daemon's shutdown
	// and fire a reminder into a process on its way out. The daemon already
	// stops its watcher first; this keeps the invariant here, where it can be
	// checked, rather than in the caller.
	if c.stopped {
		c.mu.Unlock()
		return
	}
	c.longBreakEvery = cfg.Pomodoro.LongBreakEvery
	c.floatWindowWhenWaiting = cfg.FloatWindowWhenWaiting
	c.timer.SetPausedTooLongAfter(pausedTooLongAfter(cfg))
	// morning_reminder_pending is deliberately not reloaded: it answers
	// whether today's reminder is owed at start-up, a question Start has
	// already settled by the time any reload arrives.
	c.scheduler = scheduler.New(config.ScheduleDayTimes(cfg.Schedule))
	c.reminder.setPolicy(reminder.NewPolicy(
		time.Duration(cfg.RepeatSecs)*time.Second,
		time.Duration(cfg.RepeatLimitSecs)*time.Second,
	))
	// The timer publishes on its own once the durations land, but it does so
	// asynchronously; the explicit publish below is what makes ApplyConfig's
	// effect visible by the time it returns.
	c.timer.ApplyDurations(
		cfg.Pomodoro.WorkMinutes,
		cfg.Pomodoro.ShortBreakMinutes,
		cfg.Pomodoro.LongBreakMinutes,
		cfg.Pomodoro.LongBreakEvery,
	)
	c.mu.Unlock()
	c.publish()
}

// pausedTooLongAfter is how long a pause may last before the timer calls it
// forgotten, as the config writes it.
func pausedTooLongAfter(cfg config.Config) time.Duration {
	return time.Duration(cfg.PausedTooLongMinutes) * time.Minute
}

// setPolicy changes how often the reminder repeats. A reminder already
// ringing keeps its current loop: the new policy governs the next one, so an
// edit cannot silence a nudge the user has not answered.
func (r *outstandingReminder) setPolicy(policy reminder.Policy) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.policy = policy
}
