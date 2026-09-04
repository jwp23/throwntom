package engine

import (
	"encoding/json"
	"testing"
	"time"
)

// A meeting is time the user spends away from the timer but still at work, so
// unlike lunch it credits pomodoros rather than ending the block. These tests
// pin the credit arithmetic and the block crossover the credits can cause.

func TestMeetingStateRoundTripsThroughItsName(t *testing.T) {
	data, err := json.Marshal(Meeting)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if string(data) != `"meeting"` {
		t.Fatalf("marshalled as %s, want \"meeting\"", data)
	}
	var back State
	if err := json.Unmarshal(data, &back); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if back != Meeting {
		t.Fatalf("round-tripped to %v, want Meeting", back)
	}
}

func TestStartMeetingEntersMeetingFromAnyState(t *testing.T) {
	for _, tc := range []struct {
		name  string
		setup func(*Engine)
	}{
		{"idle", func(*Engine) {}},
		{"work", func(e *Engine) { e.StartWork() }},
		{"short break", func(e *Engine) { e.StartWork(); e.MarkPeriodComplete(); e.ConfirmNext() }},
		{"lunch", func(e *Engine) { e.StartLunch() }},
		{"paused", func(e *Engine) { e.StartWork(); e.Pause() }},
		{"awaiting confirm", func(e *Engine) { e.StartWork(); e.MarkPeriodComplete() }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			e := New(25, 5, 15, 4)
			tc.setup(e)
			e.StartMeeting()
			if e.State() != Meeting {
				t.Fatalf("state is %v, want Meeting", e.State())
			}
		})
	}
}

// The credit a meeting earns is its length in pomodoros, rounded to the
// nearest with a half rounding up. A 60-minute meeting on a 25-minute
// pomodoro is 2.4 pomodoros and credits 2, which is the ruling this whole
// feature was specified against.
func TestMeetingCreditsRoundToTheNearestPomodoro(t *testing.T) {
	for _, tc := range []struct {
		elapsed     time.Duration
		workMinutes int
		want        int
	}{
		{60 * time.Minute, 25, 2},
		{30 * time.Minute, 25, 1},
		{40 * time.Minute, 25, 2},
		{10 * time.Minute, 25, 0},
		{75 * time.Minute, 25, 3},
		// Exactly half a pomodoro rounds up, and a hair under it rounds down.
		{5 * time.Minute, 10, 1},
		{299 * time.Second, 10, 0},
		{0, 25, 0},
	} {
		if got := MeetingCredits(tc.elapsed, tc.workMinutes); got != tc.want {
			t.Errorf("MeetingCredits(%v, %d) = %d, want %d", tc.elapsed, tc.workMinutes, got, tc.want)
		}
	}
}

func TestCompletedMeetingAwaitsConfirm(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartMeeting()
	e.CompleteMeeting(30 * time.Minute)
	if e.State() != AwaitingConfirm {
		t.Fatalf("state is %v, want AwaitingConfirm", e.State())
	}
}

func TestCompletedMeetingCreditsTheDayAndTheBlock(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartMeeting()
	e.CompleteMeeting(60 * time.Minute)
	if got := e.CompletedToday(); got != 2 {
		t.Fatalf("completed today is %d, want 2", got)
	}
	if got := e.WorkSessionsInBlock(); got != 2 {
		t.Fatalf("work sessions in block is %d, want 2", got)
	}
}

// A meeting is worked time, not rested time, so the phase after it is work
// again rather than the break a finished pomodoro earns.
func TestMeetingIsFollowedByWork(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.StartMeeting()
	e.CompleteMeeting(30 * time.Minute)
	if next := e.NextPhase(); next != Work {
		t.Fatalf("next phase is %v, want Work", next)
	}
	e.ConfirmNext()
	if e.State() != Work {
		t.Fatalf("state is %v, want Work", e.State())
	}
}

// The crossover ruling: three pomodoros done in a block of four, then a
// 60-minute meeting credits two. The fourth completes the block, so the long
// break follows, and the fifth carries into the next block as its first — the
// next worked pomodoro is that block's second.
func TestMeetingCreditsCrossingTheBlockBoundaryEarnTheLongBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for range 3 {
		workAndRest(e)
	}
	if got := e.WorkSessionsInBlock(); got != 3 {
		t.Fatalf("work sessions in block is %d, want 3 before the meeting", got)
	}

	e.StartMeeting()
	e.CompleteMeeting(60 * time.Minute)
	if got := e.WorkSessionsInBlock(); got != 5 {
		t.Fatalf("work sessions in block is %d, want 5 after the meeting", got)
	}
	if next := e.NextPhase(); next != LongBreak {
		t.Fatalf("next phase is %v, want LongBreak", next)
	}

	e.ConfirmNext()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	if e.State() != Work {
		t.Fatalf("state after the long break is %v, want Work", e.State())
	}
	e.MarkPeriodComplete()
	if got := e.WorkSessionsInBlock(); got != 6 {
		t.Fatalf("work sessions in block is %d, want 6 -- the second of the new block", got)
	}
	if next := e.NextPhase(); next != ShortBreak {
		t.Fatalf("next phase is %v, want ShortBreak -- the block is not done again yet", next)
	}
}

// A meeting whose credits land exactly on the boundary ends the block too;
// nothing about the boundary requires being jumped over rather than hit.
func TestMeetingCreditsLandingOnTheBoundaryEarnTheLongBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for range 2 {
		workAndRest(e)
	}
	e.StartMeeting()
	e.CompleteMeeting(50 * time.Minute)
	if got := e.WorkSessionsInBlock(); got != 4 {
		t.Fatalf("work sessions in block is %d, want 4", got)
	}
	if next := e.NextPhase(); next != LongBreak {
		t.Fatalf("next phase is %v, want LongBreak", next)
	}
}

// A meeting too short to credit anything leaves the count where it was, and
// the user goes back to work.
func TestMeetingTooShortToCreditChangesNoCount(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	workAndRest(e)
	e.StartMeeting()
	e.CompleteMeeting(5 * time.Minute)
	if got := e.CompletedToday(); got != 1 {
		t.Fatalf("completed today is %d, want 1", got)
	}
	if got := e.WorkSessionsInBlock(); got != 1 {
		t.Fatalf("work sessions in block is %d, want 1", got)
	}
	if next := e.NextPhase(); next != Work {
		t.Fatalf("next phase is %v, want Work", next)
	}
}

// A meeting does not end the block the way lunch does: the pomodoros done
// before it still count toward the long break.
func TestMeetingKeepsTheBlockLunchWouldEnd(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for range 2 {
		workAndRest(e)
	}
	e.StartMeeting()
	if got := e.WorkSessionsInBlock(); got != 2 {
		t.Fatalf("work sessions in block is %d, want 2 -- a meeting keeps the block", got)
	}
}

// A stop during a meeting suspends the cycle like any other phase, and the
// phase it owes on the way back is what the meeting's credits earned.
func TestOwedPhaseAfterAMeetingFollowsItsCredits(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for range 3 {
		workAndRest(e)
	}
	e.StartMeeting()
	e.CompleteMeeting(60 * time.Minute)
	e.Stop()
	if owed := e.OwedPhase(); owed != LongBreak {
		t.Fatalf("owed phase is %v, want LongBreak", owed)
	}
}

func TestMeetingCanBePausedAndResumed(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartMeeting()
	if !e.Pause() {
		t.Fatal("a running meeting refused to pause")
	}
	if !e.Resume() {
		t.Fatal("a paused meeting refused to resume")
	}
	if e.State() != Meeting {
		t.Fatalf("state is %v, want Meeting", e.State())
	}
}

// Both boundaries a meeting can reach have to survive a restore, or the
// session file is discarded and the meeting in flight is lost.
func TestSnapshotsReachedThroughAMeetingAreValid(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartMeeting()
	if reason := e.Snapshot().Invalid(); reason != "" {
		t.Fatalf("a running meeting is invalid: %s", reason)
	}
	e.Pause()
	if reason := e.Snapshot().Invalid(); reason != "" {
		t.Fatalf("a paused meeting is invalid: %s", reason)
	}
	e.Resume()
	e.CompleteMeeting(30 * time.Minute)
	if reason := e.Snapshot().Invalid(); reason != "" {
		t.Fatalf("a meeting awaiting confirm is invalid: %s", reason)
	}
}

// Restoring has to bring back the credits the meeting earned, so the break the
// far side of a restart is the one the meeting bought.
func TestRestoreKeepsWhatAMeetingCredited(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for range 3 {
		workAndRest(e)
	}
	e.StartMeeting()
	e.CompleteMeeting(60 * time.Minute)

	restored := New(25, 5, 15, 4)
	restored.Restore(e.Snapshot())
	if next := restored.NextPhase(); next != LongBreak {
		t.Fatalf("next phase after restore is %v, want LongBreak", next)
	}
}
