package core

import (
	"context"
	"errors"
	"sync"
	"time"

	"github.com/jwp23/throwntom/v3/internal/notifier"
	"github.com/jwp23/throwntom/v3/internal/reminder"
	"github.com/jwp23/throwntom/v3/internal/scheduler"
)

// reminderKind is which nudge is outstanding. At most one is, because the
// morning reminder only fires while idle and the cycle reminder only at
// awaiting_confirm.
type reminderKind int

const (
	reminderNone reminderKind = iota
	reminderMorning
	reminderCycle
)

func (k reminderKind) sound() string {
	if k == reminderMorning {
		return "morning"
	}
	return "default"
}

func (k reminderKind) label() string {
	switch k {
	case reminderMorning:
		return "morning"
	case reminderCycle:
		return "cycle"
	default:
		return ""
	}
}

// stopper cancels a callback scheduled through after.
type stopper interface {
	Stop() bool
}

var errNoReminder = errors.New("nothing to snooze: no reminder is outstanding")

// outstandingReminder is the one reminder the daemon can be waiting on. kind
// says whether one is outstanding; snoozeUntil says whether it is quiet. now
// and after are the only clock it uses, so a test can drive its deadlines.
type outstandingReminder struct {
	mu             sync.Mutex
	kind           reminderKind
	snoozeUntil    time.Time
	lastTriggerDay string
	loopCancel     context.CancelFunc
	snoozeTimer    stopper
	policy         reminder.Policy
	sound          func(reminderKind) error
	now            func() time.Time
	after          func(time.Duration, func()) stopper
	// onChange runs after a change an observer can see, with mu released.
	onChange func()
}

func newOutstandingReminder(policy reminder.Policy, n notifier.Notifier) *outstandingReminder {
	return &outstandingReminder{
		policy: policy,
		sound:  func(k reminderKind) error { return n.PlaySound(k.sound()) },
		now:    time.Now,
		after:  func(d time.Duration, fn func()) stopper { return time.AfterFunc(d, fn) },
	}
}

func (r *outstandingReminder) notifyChange() {
	r.mu.Lock()
	fn := r.onChange
	r.mu.Unlock()
	if fn != nil {
		fn()
	}
}

// raise makes kind the outstanding reminder and starts ringing. Raising the
// kind that is already outstanding changes nothing, so a repeated schedule
// tick or a restore cannot ring twice or cut a snooze short.
func (r *outstandingReminder) raise(kind reminderKind) {
	r.mu.Lock()
	if r.kind == kind {
		r.mu.Unlock()
		return
	}
	r.quietLocked()
	r.kind = kind
	r.startLoopLocked()
	r.mu.Unlock()
	r.notifyChange()
}

// suppress silences the outstanding reminder until the deadline, replacing
// any earlier deadline, and reports which kind it suppressed.
func (r *outstandingReminder) suppress(until time.Time) (reminderKind, error) {
	r.mu.Lock()
	if r.kind == reminderNone {
		r.mu.Unlock()
		return reminderNone, errNoReminder
	}
	kind := r.kind
	r.quietLocked()
	r.snoozeUntil = until
	r.snoozeTimer = r.after(until.Sub(r.now()), func() { r.resume(until) })
	r.mu.Unlock()
	r.notifyChange()
	return kind, nil
}

// resume ends the snooze that set deadline until. A deadline that was
// cancelled or replaced in the meantime no longer matches and does nothing.
func (r *outstandingReminder) resume(until time.Time) {
	r.mu.Lock()
	if r.kind == reminderNone || !r.snoozeUntil.Equal(until) {
		r.mu.Unlock()
		return
	}
	r.snoozeUntil = time.Time{}
	r.snoozeTimer = nil
	r.startLoopLocked()
	r.mu.Unlock()
	r.notifyChange()
}

// cancel retires the outstanding reminder, ringing or snoozed.
func (r *outstandingReminder) cancel() {
	r.mu.Lock()
	changed := r.kind != reminderNone
	r.quietLocked()
	r.kind = reminderNone
	r.mu.Unlock()
	if changed {
		r.notifyChange()
	}
}

// skipToday cancels and marks the morning reminder as already fired today.
func (r *outstandingReminder) skipToday(now time.Time) {
	r.mu.Lock()
	r.lastTriggerDay = dayKey(now)
	r.mu.Unlock()
	r.cancel()
}

// shouldRaiseMorning reports whether the schedule wants the morning reminder
// now, at most once per day and never during a snooze. Callers check that the
// timer is idle first.
func (r *outstandingReminder) shouldRaiseMorning(now time.Time, sched *scheduler.Scheduler) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	if !r.snoozeUntil.IsZero() {
		return false
	}
	key := dayKey(now)
	if !sched.ShouldTrigger(now) || key == r.lastTriggerDay {
		return false
	}
	r.lastTriggerDay = key
	return true
}

func (r *outstandingReminder) outstanding() reminderKind {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.kind
}

func (r *outstandingReminder) snoozeDeadline() (time.Time, bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.snoozeUntil, !r.snoozeUntil.IsZero()
}

// quietLocked stops the loop and the snooze timer and clears the deadline,
// leaving kind for the caller to decide. Callers must hold r.mu.
func (r *outstandingReminder) quietLocked() {
	if r.loopCancel != nil {
		r.loopCancel()
		r.loopCancel = nil
	}
	if r.snoozeTimer != nil {
		r.snoozeTimer.Stop()
		r.snoozeTimer = nil
	}
	r.snoozeUntil = time.Time{}
}

// startLoopLocked rings for the outstanding kind until cancelled or the
// policy's bound is reached. Callers must hold r.mu.
func (r *outstandingReminder) startLoopLocked() {
	ctx, cancel := context.WithCancel(context.Background())
	r.loopCancel = cancel
	kind := r.kind
	loop := reminder.New(r.policy, func() error { return r.sound(kind) })
	go loop.Run(ctx)
}

func dayKey(now time.Time) string {
	return now.Format("2006-01-02")
}
