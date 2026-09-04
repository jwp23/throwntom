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
	// Lunch is the break the user chooses rather than the one a finished
	// pomodoro earns. No transition leads to it; only StartLunch does.
	Lunch
	// Meeting is time spent away from the timer but still at work. Like lunch
	// it is chosen rather than earned, and only StartMeeting leads to it;
	// unlike lunch it is worked time, so it credits pomodoros instead of
	// ending the block.
	Meeting
	AwaitingConfirm
	Paused
)

var stateNames = [...]string{
	Idle:            "idle",
	Work:            "work",
	ShortBreak:      "short_break",
	LongBreak:       "long_break",
	Lunch:           "lunch",
	Meeting:         "meeting",
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
	// dayEnded records that the user declared the work day over, which no
	// other idle state means. It is the only way a client can tell "idle,
	// ready to go" from "idle, done until tomorrow".
	dayEnded bool
	workDate time.Time
	// skipped records that the phase behind lastPhase was cut short by the
	// user rather than served. A skipped work period earns no long break, and
	// no phase skipped this way counts as completed. Any completed period
	// clears it, as do the verbs that reset the cycle.
	//
	// The invariant is narrow: whenever lastPhase is Work, skipped describes
	// that work period. Only MarkPeriodComplete and SkipPhase can make
	// lastPhase Work while a break decision is pending, and both write the
	// flag as they do it; Stop and AdvanceDay carry lastPhase and the flag
	// forward together. It is deliberately left standing through ConfirmNext,
	// Resume and StartWork, which set lastPhase without touching it — safe
	// only because breakAfterWork is the sole reader and only runs when
	// lastPhase is Work. Read it anywhere else and it may be stale.
	skipped bool
	// lastCredit is how many pomodoros the phase behind lastPhase added to the
	// block. An ordinary pomodoro credits one; a meeting credits its length
	// rounded to the nearest pomodoro, which can be several at once or none.
	// It is what lets blockBoundaryCrossed tell a block that was completed
	// from one that was jumped clean over, which a count on its own cannot.
	lastCredit int
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
//
// The day's totals are not touched. Starting work opens the work day, and
// SkipToday closes it, so work_day_started swings freely within a single day
// and cannot stand in for a day boundary; AdvanceDay owns that, by the work
// date, and resets the totals there.
func (e *Engine) StartWork() {
	next := e.OwedPhase()
	e.workDayStarted = true
	e.dayEnded = false
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
	case Meeting:
		return e.nextAfterMeeting()
	case ShortBreak, LongBreak, Lunch:
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
	if e.blockBoundaryCrossed() {
		return LongBreak
	}
	return ShortBreak
}

// nextAfterMeeting reports the phase a finished meeting leads to. A meeting is
// credited work rather than rest, so the user goes back to work after one
// instead of taking the short break a pomodoro earns. The long break is the
// exception: it belongs to the block rather than to the pomodoro before it, so
// credits that carry the block over its boundary earn it like any others.
func (e *Engine) nextAfterMeeting() State {
	if e.blockBoundaryCrossed() {
		return LongBreak
	}
	return Work
}

// blockBoundaryCrossed reports whether the credits of the phase behind
// lastPhase carried the block count over a multiple of longBreakEvery. A
// pomodoro credits one and so can only land on the multiple; a meeting can
// credit several at once and jump it without landing on it, which a bare
// remainder test would miss — and would then go on missing every boundary
// after it, since the count never returns to a multiple.
func (e *Engine) blockBoundaryCrossed() bool {
	if e.lastCredit <= 0 || e.workSessionsBlock <= 0 {
		return false
	}
	return e.workSessionsBlock/e.longBreakEvery > (e.workSessionsBlock-e.lastCredit)/e.longBreakEvery
}

func (e *Engine) StartNewCycle() {
	e.dayEnded = false
	e.skipped = false
	e.workDayStarted = true
	e.workSessionsBlock = 0
	e.lastCredit = 0
	e.state = Work
	e.lastPhase = Work
	e.pausedFrom = Idle
}

// StartLunch takes the user to lunch from wherever they are. Lunch is chosen
// rather than earned, so no transition leads to it and nothing has to be owed
// for it to begin.
//
// Taking it ends the block: the count of pomodoros toward the long break
// starts again, exactly as StartNewCycle resets it, so the pomodoro after
// lunch is the first of a fresh block. The day's total is untouched — those
// pomodoros were worked. The reset happens here, at the start of lunch, rather
// than when lunch ends: the block is over the moment the user leaves for it,
// and a count left standing through lunch would promise a long break the far
// side of it that will not come.
func (e *Engine) StartLunch() {
	e.skipped = false
	e.dayEnded = false
	e.workDayStarted = true
	e.workSessionsBlock = 0
	e.lastCredit = 0
	e.state = Lunch
	e.lastPhase = Lunch
	e.pausedFrom = Idle
}

// StartMeeting takes the user into a meeting from wherever they are. Like
// lunch it is chosen rather than earned, so nothing has to be owed for it to
// begin and no transition leads to it.
//
// Unlike lunch it leaves the block alone. A meeting is worked time — it
// credits pomodoros when it ends — so the pomodoros done before it are still
// pomodoros of the same block, and the long break they are working toward is
// still coming.
func (e *Engine) StartMeeting() {
	e.skipped = false
	e.dayEnded = false
	e.workDayStarted = true
	e.state = Meeting
	e.lastPhase = Meeting
	e.pausedFrom = Idle
}

// MeetingCredits reports how many pomodoros a meeting of the given length is
// worth: its length in pomodoros, rounded to the nearest, with exactly half
// rounding up. A meeting shorter than half a pomodoro is worth none.
//
// The arithmetic is integer so the boundary is exact — a meeting of precisely
// half a pomodoro credits one, and the float rounding that would decide such a
// case by the last bit of a division never runs.
func MeetingCredits(elapsed time.Duration, workMinutes int) int {
	work := time.Duration(workMinutes) * time.Minute
	if work <= 0 || elapsed <= 0 {
		return 0
	}
	return int((2*elapsed + work) / (2 * work))
}

// CompleteMeeting ends a meeting that has run its course or been cut short,
// crediting the time actually spent in it. The credit lands in the day's total
// and in the block alike: it is work that was done, so it counts toward the
// long break exactly as a worked pomodoro does.
//
// A meeting too short to credit anything still ends here rather than being
// refused; the user was in it, and the phase has to end somewhere.
func (e *Engine) CompleteMeeting(elapsed time.Duration) {
	if e.state != Meeting {
		return
	}
	credits := MeetingCredits(elapsed, e.workMinutes)
	e.skipped = false
	e.lastCredit = credits
	e.completedToday += credits
	e.workSessionsBlock += credits
	e.lastPhase = Meeting
	e.state = AwaitingConfirm
}

func (e *Engine) MarkPeriodComplete() {
	e.skipped = false
	if e.state == Work {
		e.completedToday++
		e.workSessionsBlock++
		e.lastCredit = 1
		e.lastPhase = e.state
		e.state = AwaitingConfirm
		return
	}
	if e.state == ShortBreak || e.state == LongBreak || e.state == Lunch {
		e.lastCredit = 0
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
	switch e.lastPhase {
	case Work:
		return e.breakAfterWork()
	case Meeting:
		return e.nextAfterMeeting()
	default:
		return Work
	}
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

// SkipToday ends the work day: the timer goes idle and stays there, and the
// day is marked over so nothing reminds the user again until tomorrow.
func (e *Engine) SkipToday() {
	e.skipped = false
	e.lastCredit = 0
	e.state = Idle
	e.lastPhase = Idle
	e.pausedFrom = Idle
	e.workDayStarted = false
	e.dayEnded = true
}

// SkipPhase ends the running phase early at the user's request, reaching the
// same boundary a phase that ran its course reaches: the next stage, awaiting
// confirmation. Nothing is credited — a skipped pomodoro was not worked, so
// counting it would inflate the day's total and the long-break cycle alike.
// It reports whether a phase was running to skip.
//
// Meeting is deliberately absent: a meeting cut short still credits the time
// that was spent in it, which is CompleteMeeting's job and needs the elapsed
// time this method is not given. Adding Meeting here would end the phase while
// silently discarding its credit.
func (e *Engine) SkipPhase() bool {
	switch e.state {
	case Work, ShortBreak, LongBreak, Lunch:
		e.lastPhase = e.state
		e.state = AwaitingConfirm
		e.skipped = true
		e.lastCredit = 0
		return true
	default:
		return false
	}
}

func (e *Engine) Pause() bool {
	switch e.state {
	case Work, ShortBreak, LongBreak, Lunch, Meeting:
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
	DayEnded       bool      `json:"day_ended"`
	WorkDate       time.Time `json:"work_date"`
	// Skipped reports that the phase in LastPhase was skipped rather than
	// served, so nothing about it should be recorded as completed.
	Skipped bool `json:"skipped"`
	// LastCredit is how many pomodoros the phase in LastPhase credited to the
	// block, which is what decides whether the block's long break is owed.
	LastCredit int `json:"last_credit"`
}

func (e *Engine) Snapshot() Snapshot {
	return Snapshot{
		State:          e.state,
		LastPhase:      e.lastPhase,
		PausedFrom:     e.pausedFrom,
		WorkSessions:   e.workSessionsBlock,
		CompletedToday: e.completedToday,
		WorkDayStarted: e.workDayStarted,
		DayEnded:       e.dayEnded,
		WorkDate:       e.workDate,
		Skipped:        e.skipped,
		LastCredit:     e.lastCredit,
	}
}

// Invalid reports why s is not reachable from the engine's own transitions,
// or "" if it is. A hand-edited or concurrently-written session file can hold
// combinations no sequence of StartWork/MarkPeriodComplete/ConfirmNext/Pause
// ever produces; restoring one verbatim can resurrect a reminder loop with
// nothing behind it.
func (s Snapshot) Invalid() string {
	// Nothing here relates completed_today to last_phase: skipping the first
	// pomodoro of the day legitimately reaches a break with none completed.
	if !s.WorkDayStarted && (s.State != Idle || s.LastPhase != Idle) {
		return "work_day_started is false but state/last_phase is not idle"
	}
	// Only SkipToday sets day_ended, and it closes the work day and goes idle in
	// the same move; every other transition clears it.
	if s.DayEnded && (s.State != Idle || s.WorkDayStarted) {
		return "day_ended is true but the work day is not closed and idle"
	}
	if s.State == AwaitingConfirm {
		switch s.LastPhase {
		case Work, ShortBreak, LongBreak, Lunch, Meeting:
		default:
			return "awaiting_confirm with an unreachable last_phase"
		}
	}
	if s.State == Paused && !isTimedPhase(s.PausedFrom) {
		return "paused with an unreachable paused_from"
	}
	return ""
}

// isTimedPhase reports whether s is one of the phases that run on a clock,
// which are the only ones a confirm or a pause can have come from.
func isTimedPhase(s State) bool {
	switch s {
	case Work, ShortBreak, LongBreak, Lunch, Meeting:
		return true
	default:
		return false
	}
}

func (e *Engine) Restore(s Snapshot) {
	e.state = s.State
	e.lastPhase = s.LastPhase
	e.pausedFrom = s.PausedFrom
	e.workSessionsBlock = s.WorkSessions
	e.completedToday = s.CompletedToday
	e.workDayStarted = s.WorkDayStarted
	e.dayEnded = s.DayEnded
	e.workDate = s.WorkDate
	e.skipped = s.Skipped
	e.lastCredit = s.LastCredit
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
	e.lastCredit = 0
	e.dayEnded = false
	// A phase in flight when the day turns carries into the new day: it is
	// running, paused or waiting to be confirmed now, so the new day's work has
	// already begun, and lastPhase and skipped describe that phase rather than
	// a debt. Forgetting them here leaves a snapshot the engine's own
	// transitions could not reach, and the next start discards the session
	// whole. Only an idle engine crosses owing something, and a new day owes
	// nothing: yesterday's suspended cycle does not carry over.
	if e.state == Idle {
		e.workDayStarted = false
		e.lastPhase = Idle
		e.skipped = false
	}
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
