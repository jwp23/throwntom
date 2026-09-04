package core

import (
	"context"
	"errors"
	"sync"
	"time"

	"github.com/jwp23/throwntom/v3/internal/notifier"
	"github.com/jwp23/throwntom/v3/internal/reminder"
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
	case reminderNone:
		return ""
	}
	return ""
}

// stopper cancels a callback scheduled through after.
type stopper interface {
	Stop() bool
}

var (
	errNoReminder = errors.New("nothing to snooze: no reminder is outstanding")
	errNoSnooze   = errors.New("nothing to unsnooze: no snooze is active")
)

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
	rings          int
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
	r.rings = 0
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
	r.endSuppressionLocked()
	r.mu.Unlock()
	r.notifyChange()
}

// unsuppress ends the snooze now instead of at its deadline, and reports which
// kind it woke. A snooze only silences the reminder — the reminder itself was
// never answered (ADR-004) — so ending the suppression early leaves it
// outstanding and ringing, exactly as its deadline would have. That is the
// whole difference from cancel, which retires the reminder as well.
func (r *outstandingReminder) unsuppress() (reminderKind, error) {
	r.mu.Lock()
	if r.kind == reminderNone || r.snoozeUntil.IsZero() {
		r.mu.Unlock()
		return reminderNone, errNoSnooze
	}
	kind := r.kind
	r.endSuppressionLocked()
	r.mu.Unlock()
	r.notifyChange()
	return kind, nil
}

// endSuppressionLocked ends a snooze and starts the reminder ringing again. It
// is what both ways out of a snooze share, so ending one early and letting it
// expire cannot drift apart. Going quiet first is how the deadline is dropped;
// on the expiry path that timer has already fired and stopping it does nothing.
// Callers must hold r.mu.
func (r *outstandingReminder) endSuppressionLocked() {
	r.quietLocked()
	r.startLoopLocked()
}

// cancel retires the outstanding reminder, ringing or snoozed.
func (r *outstandingReminder) cancel() {
	r.mu.Lock()
	changed := r.kind != reminderNone
	r.quietLocked()
	r.kind = reminderNone
	r.rings = 0
	r.mu.Unlock()
	if changed {
		r.notifyChange()
	}
}

// skipToday cancels and marks the morning reminder as already fired today.
func (r *outstandingReminder) skipToday(now time.Time) {
	r.markTriggeredToday(now)
	r.cancel()
}

// markTriggeredToday records that the morning reminder is owed no more
// today, without touching whatever reminder is outstanding. Restoring a
// session that was already past the morning uses it.
func (r *outstandingReminder) markTriggeredToday(now time.Time) {
	r.mu.Lock()
	r.lastTriggerDay = dayKey(now)
	r.mu.Unlock()
}

// shouldRaiseMorning reports whether the morning reminder is owed now, at most
// once per day and never during a snooze, and claims the day when it says yes.
// Callers check that the timer is idle first.
//
// scheduleDue is the caller's reading of the schedule, because the two callers
// ask different questions of it: a schedule tick rings on the minute the
// schedule names, while a daemon starting up has to ring for a morning it
// missed entirely, so it asks whether that minute has already passed today.
// What must not differ is the once-a-day record, which is why it lives here.
func (r *outstandingReminder) shouldRaiseMorning(now time.Time, scheduleDue bool) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	if !r.snoozeUntil.IsZero() {
		return false
	}
	key := dayKey(now)
	if !scheduleDue || key == r.lastTriggerDay {
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
	// Retire any loop still running first. Every caller today reaches this with
	// none, but nothing in the type says so, and the failure if that ever stops
	// holding is a leaked goroutine ringing alongside its replacement.
	if r.loopCancel != nil {
		r.loopCancel()
	}
	ctx, cancel := context.WithCancel(context.Background())
	r.loopCancel = cancel
	go reminder.New(r.policy, r.loopNotify(ctx)).Run(ctx)
}

// loopNotify is what one ring loop alerts through. It carries the loop's own
// ctx, which is the loop's identity: quietLocked retires a loop by cancelling
// that ctx, so ctx is how a later alert can tell whether the loop it came from
// is still the one this reminder is running.
//
// The first alert is promised. Raising a reminder means it rings, and a raise
// followed closely by a snooze or a cancel must not turn that into a coin
// flip decided by when the goroutine happened to be scheduled. Every alert
// after it is checked, because that is where a stray belongs.
func (r *outstandingReminder) loopNotify(ctx context.Context) func() error {
	promised := true
	return func() error {
		first := promised
		promised = false
		return r.ring(ctx, first)
	}
}

// ring is one alert of the loop ctx belongs to. The daemon plays nothing
// (ADR-007), so the ring has to leave a mark a client can read: the count is
// what turns the daemon's cadence into a chime somewhere else. The sound call
// stays because a program that owns its own core - the TUI - is its own
// client.
//
// A retired loop rings no more. Cancelling one is not synchronous: Loop.Run
// selects over ctx.Done() and its ticker, so a tick already due can be taken
// instead of the cancel and land here after the reminder was snoozed or
// retired. Testing ctx inside the same critical section that raises the count
// is what settles that order, because quietLocked cancels while holding mu:
// an alert that finds ctx live got here before the cancel. The owner decides
// whether an alert counts (ADR-004), not the loop.
func (r *outstandingReminder) ring(loop context.Context, promised bool) error {
	r.mu.Lock()
	if !promised && loop.Err() != nil {
		r.mu.Unlock()
		return nil
	}
	kind := r.kind
	r.rings++
	r.mu.Unlock()
	err := r.sound(kind)
	r.notifyChange()
	return err
}

// ringCount is how many chimes the outstanding wait has asked for. It resets
// with the wait, so a client that has heard n rings can sound the rest.
func (r *outstandingReminder) ringCount() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.rings
}

func dayKey(now time.Time) string {
	return now.Format("2006-01-02")
}
