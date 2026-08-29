package core

import (
	"time"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/reminder"
	"github.com/jwp23/throwntom/v3/internal/scheduler"
)

// ApplyConfig puts a reloaded config in force at once, in-flight phase
// included: ADR-006 (3). Everything the daemon derives from config is
// rebuilt, so an edit never needs a restart to take effect.
func (c *Core) ApplyConfig(cfg config.Config) {
	c.mu.Lock()
	c.longBreakEvery = cfg.Pomodoro.LongBreakEvery
	c.morningPending = cfg.MorningReminderPending
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

// setPolicy changes how often the reminder repeats. A reminder already
// ringing keeps its current loop: the new policy governs the next one, so an
// edit cannot silence a nudge the user has not answered.
func (r *outstandingReminder) setPolicy(policy reminder.Policy) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.policy = policy
}
