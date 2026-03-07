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
	snoozeUntil       time.Time
	workSessionsBlock int
	completedToday    int
	workDayStarted    bool
	workDate          time.Time
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

func (e *Engine) StartWork() {
	if !e.workDayStarted {
		e.completedToday = 0
		e.workDayStarted = true
		e.workSessionsBlock = 0
	}
	e.state = Work
	e.lastPhase = Work
}

func (e *Engine) StartNewCycle() {
	e.workDayStarted = true
	e.workSessionsBlock = 0
	e.state = Work
	e.lastPhase = Work
	e.pausedFrom = Idle
}

func (e *Engine) MarkPeriodComplete() {
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
	if e.lastPhase == Work {
		if e.workSessionsBlock%e.longBreakEvery == 0 {
			e.state = LongBreak
			e.lastPhase = LongBreak
			return
		}
		e.state = ShortBreak
		e.lastPhase = ShortBreak
		return
	}
	e.state = Work
	e.lastPhase = Work
}

func (e *Engine) Snooze(d time.Duration) {
	e.snoozeUntil = time.Now().Add(d)
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

func (e *Engine) SkipToday() {
	e.state = Idle
	e.lastPhase = Idle
	e.pausedFrom = Idle
	e.workDayStarted = false
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
	}
}

func (e *Engine) Restore(s Snapshot) {
	e.state = s.State
	e.lastPhase = s.LastPhase
	e.pausedFrom = s.PausedFrom
	e.workSessionsBlock = s.WorkSessions
	e.completedToday = s.CompletedToday
	e.workDayStarted = s.WorkDayStarted
	e.workDate = s.WorkDate
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
	e.workDate = now
}

func (e *Engine) Stop() {
	e.state = Idle
	e.lastPhase = Idle
	e.pausedFrom = Idle
	e.snoozeUntil = time.Time{}
}
