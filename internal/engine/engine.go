package engine

import "time"

type State int

const (
	Idle State = iota
	Work
	ShortBreak
	LongBreak
	AwaitingConfirm
	Paused
)

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

func (e *Engine) SnoozeUntil() time.Time {
	return e.snoozeUntil
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

func (e *Engine) Stop() {
	e.state = Idle
	e.lastPhase = Idle
	e.pausedFrom = Idle
	e.snoozeUntil = time.Time{}
}
