package engine

import (
	"fmt"
	"time"
)

type State int

const (
	Idle State = iota
	Work
	ShortBreak
	LongBreak
	AwaitingConfirm
	Paused
)

var stateNames = [...]string{
	Idle:            "idle",
	Work:            "work",
	ShortBreak:      "short_break",
	LongBreak:       "long_break",
	AwaitingConfirm: "awaiting_confirm",
	Paused:          "paused",
}

var stateFromName = func() map[string]State {
	m := make(map[string]State, len(stateNames))
	for i, name := range stateNames {
		m[name] = State(i)
	}
	return m
}()

func (s State) String() string {
	if int(s) < len(stateNames) {
		return stateNames[s]
	}
	return fmt.Sprintf("State(%d)", s)
}

func StateFromString(name string) (State, bool) {
	s, ok := stateFromName[name]
	if !ok {
		return Idle, false
	}
	return s, true
}

func (s State) MarshalText() ([]byte, error) {
	return []byte(s.String()), nil
}

func (s *State) UnmarshalText(data []byte) error {
	parsed, ok := StateFromString(string(data))
	if !ok {
		return fmt.Errorf("unknown engine state: %q", data)
	}
	*s = parsed
	return nil
}

type Engine struct {
	workMinutes       int
	shortBreakMinutes int
	longBreakMinutes  int
	longBreakEvery    int
	state             State
	lastPhase         State
	pausedFrom        State
	workSessionsBlock int
	completedToday    int
	workDayStarted    bool
	workDate          time.Time
	// skipped records that the phase behind lastPhase was cut short by the
	// user rather than served. A skipped work period earns no long break, and
	// no phase skipped this way counts as completed. Any completed period
	// clears it.
	skipped bool
}

func New(workMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery int) *Engine {
	return &Engine{
		workMinutes:       workMinutes,
		shortBreakMinutes: shortBreakMinutes,
		longBreakMinutes:  longBreakMinutes,
		longBreakEvery:    longBreakEvery,
		state:             Idle,
		lastPhase:         Idle,
	}
}

func (e *Engine) State() State {
	return e.state
}

// StartWork picks the cycle back up. A stop that suspended an owed phase left
// that phase recorded in lastPhase, and it is what resumes; with nothing owed,
// work begins. A day that has not started yet owes nothing by definition.
func (e *Engine) StartWork() {
	next := e.OwedPhase()
	if !e.workDayStarted {
		e.completedToday = 0
		e.workDayStarted = true
		e.workSessionsBlock = 0
	}
	e.state = next
	e.lastPhase = next
}

// OwedPhase reports the phase a start would enter now, letting a caller
// prepare for that phase before committing to it. Only an idle engine can owe
// anything: lastPhase names the phase most recently entered, so while one is
// running, paused or awaiting confirmation it describes the present rather
// than a debt. A day that has not started owes nothing either.
func (e *Engine) OwedPhase() State {
	if !e.workDayStarted || e.state != Idle {
		return Work
	}
	return e.owedPhase()
}

// owedPhase reports the phase a suspended cycle should resume into, given the
// phase that last ran to completion. It is NextPhase's rule without
// NextPhase's requirement that the engine be sitting in AwaitingConfirm.
func (e *Engine) owedPhase() State {
	switch e.lastPhase {
	case Work:
		return e.breakAfterWork()
	case ShortBreak, LongBreak:
		return Work
	default:
		return Work
	}
}

// breakAfterWork reports which break a work period earns. Only a completed one
// can earn the long break: a skipped period left the block count untouched, so
// the count either stands at zero or still describes the block whose long
// break has already been taken. Either way the remainder lies, and the honest
// answer is the short break.
func (e *Engine) breakAfterWork() State {
	if e.skipped {
		return ShortBreak
	}
	if e.workSessionsBlock > 0 && e.workSessionsBlock%e.longBreakEvery == 0 {
		return LongBreak
	}
	return ShortBreak
}

func (e *Engine) StartNewCycle() {
	e.workDayStarted = true
	e.workSessionsBlock = 0
	e.state = Work
	e.lastPhase = Work
	e.pausedFrom = Idle
}

func (e *Engine) MarkPeriodComplete() {
	e.skipped = false
	if e.state == Work {
		e.completedToday++
		e.workSessionsBlock++
		e.lastPhase = e.state
		e.state = AwaitingConfirm
		return
	}
	if e.state == ShortBreak || e.state == LongBreak {
		e.lastPhase = e.state
		e.state = AwaitingConfirm
	}
}

func (e *Engine) ConfirmNext() {
	if e.state != AwaitingConfirm {
		return
	}
	next := e.NextPhase()
	e.state = next
	e.lastPhase = next
}

func (e *Engine) NextPhase() State {
	if e.state != AwaitingConfirm {
		return Idle
	}
	if e.lastPhase == Work {
		return e.breakAfterWork()
	}
	return Work
}

func (e *Engine) CompletedToday() int {
	return e.completedToday
}

func (e *Engine) WorkSessionsInBlock() int {
	return e.workSessionsBlock
}

func (e *Engine) LongBreakEvery() int {
	return e.longBreakEvery
}

// SetLongBreakEvery changes the cycle length, taking effect on the next long
// break the engine chooses. The count of work sessions in the block is left
// alone: those pomodoros were worked, whatever the cycle length is now.
//
// n must be positive — New has the same requirement, and NextPhase divides by
// it. Values reaching here come from a validated config; a zero would panic
// at the next transition rather than here, so callers that do not validate
// must check first.
func (e *Engine) SetLongBreakEvery(n int) {
	e.longBreakEvery = n
}

func (e *Engine) SkipToday() {
	e.state = Idle
	e.lastPhase = Idle
	e.pausedFrom = Idle
	e.workDayStarted = false
}

// SkipPhase ends the running phase early at the user's request, reaching the
// same boundary a phase that ran its course reaches: the next stage, awaiting
// confirmation. Nothing is credited — a skipped pomodoro was not worked, so
// counting it would inflate the day's total and the long-break cycle alike.
// It reports whether a phase was running to skip.
func (e *Engine) SkipPhase() bool {
	switch e.state {
	case Work, ShortBreak, LongBreak:
		e.lastPhase = e.state
		e.state = AwaitingConfirm
		e.skipped = true
		return true
	default:
		return false
	}
}

func (e *Engine) Pause() bool {
	switch e.state {
	case Work, ShortBreak, LongBreak:
		e.pausedFrom = e.state
		e.state = Paused
		return true
	default:
		return false
	}
}

func (e *Engine) Resume() bool {
	if e.state != Paused {
		return false
	}
	e.state = e.pausedFrom
	e.lastPhase = e.state
	e.pausedFrom = Idle
	return true
}

type Snapshot struct {
	State          State     `json:"state"`
	LastPhase      State     `json:"last_phase"`
	PausedFrom     State     `json:"paused_from"`
	WorkSessions   int       `json:"work_sessions"`
	CompletedToday int       `json:"completed_today"`
	WorkDayStarted bool      `json:"work_day_started"`
	WorkDate       time.Time `json:"work_date"`
	// Skipped reports that the phase in LastPhase was skipped rather than
	// served, so nothing about it should be recorded as completed.
	Skipped bool `json:"skipped"`
}

func (e *Engine) Snapshot() Snapshot {
	return Snapshot{
		State:          e.state,
		LastPhase:      e.lastPhase,
		PausedFrom:     e.pausedFrom,
		WorkSessions:   e.workSessionsBlock,
		CompletedToday: e.completedToday,
		WorkDayStarted: e.workDayStarted,
		WorkDate:       e.workDate,
		Skipped:        e.skipped,
	}
}

// Invalid reports why s is not reachable from the engine's own transitions,
// or "" if it is. A hand-edited or concurrently-written session file can hold
// combinations no sequence of StartWork/MarkPeriodComplete/ConfirmNext/Pause
// ever produces; restoring one verbatim can resurrect a reminder loop with
// nothing behind it.
func (s Snapshot) Invalid() string {
	if !s.WorkDayStarted && (s.State != Idle || s.LastPhase != Idle) {
		return "work_day_started is false but state/last_phase is not idle"
	}
	if (s.LastPhase == ShortBreak || s.LastPhase == LongBreak) && s.CompletedToday == 0 {
		return "last_phase is a break but completed_today is 0"
	}
	if s.State == AwaitingConfirm {
		switch s.LastPhase {
		case Work, ShortBreak, LongBreak:
		default:
			return "awaiting_confirm with an unreachable last_phase"
		}
	}
	if s.State == Paused {
		switch s.PausedFrom {
		case Work, ShortBreak, LongBreak:
		default:
			return "paused with an unreachable paused_from"
		}
	}
	return ""
}

func (e *Engine) Restore(s Snapshot) {
	e.state = s.State
	e.lastPhase = s.LastPhase
	e.pausedFrom = s.PausedFrom
	e.workSessionsBlock = s.WorkSessions
	e.completedToday = s.CompletedToday
	e.workDayStarted = s.WorkDayStarted
	e.workDate = s.WorkDate
	e.skipped = s.Skipped
}

func IsSameDay(a, b time.Time) bool {
	y1, m1, d1 := a.Date()
	y2, m2, d2 := b.Date()
	return y1 == y2 && m1 == m2 && d1 == d2
}

func (e *Engine) AdvanceDay(now time.Time) {
	if e.workDate.IsZero() {
		e.workDate = now
		return
	}
	if IsSameDay(e.workDate, now) {
		return
	}
	e.completedToday = 0
	e.workSessionsBlock = 0
	e.workDayStarted = false
	// A new day owes nothing: yesterday's suspended cycle does not carry over.
	e.lastPhase = Idle
	e.workDate = now
}

// Stop suspends the cycle rather than abandoning it: the timer goes idle, but
// a phase that ran to completion and is awaiting its successor stays owed, so
// a later start gives back the break that was earned. Progress toward the long
// break is kept either way. A phase cut short mid-flight was never finished
// and owes nothing.
func (e *Engine) Stop() {
	if e.state != AwaitingConfirm {
		e.lastPhase = Idle
	}
	e.state = Idle
	e.pausedFrom = Idle
}
