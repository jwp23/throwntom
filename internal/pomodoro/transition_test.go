package pomodoro

import (
	"sync"
	"testing"
	"time"

	"github.com/jwp23/throwntom/v3/internal/engine"
)

// transitionRecorder captures every to-state the hook delivers, in order.
type transitionRecorder struct {
	mu   sync.Mutex
	seen []engine.State
}

func (r *transitionRecorder) record(to engine.State) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.seen = append(r.seen, to)
}

func (r *transitionRecorder) last(t *testing.T, want engine.State) {
	t.Helper()
	r.mu.Lock()
	defer r.mu.Unlock()
	if len(r.seen) == 0 || r.seen[len(r.seen)-1] != want {
		t.Fatalf("expected last transition %s, got %v", want, r.seen)
	}
}

func (r *transitionRecorder) count() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return len(r.seen)
}

func TestOnTransitionFiresSynchronouslyForVerbs(t *testing.T) {
	rec := &transitionRecorder{}
	a := New(minutes(25, 5, 15, 4))
	a.SetOnTransition(rec.record)

	a.Start()
	rec.last(t, engine.Work)
	if !a.Pause() {
		t.Fatal("pause refused")
	}
	rec.last(t, engine.Paused)
	if !a.Resume() {
		t.Fatal("resume refused")
	}
	rec.last(t, engine.Work)
	a.CompletePeriod()
	rec.last(t, engine.AwaitingConfirm)
	a.Confirm()
	rec.last(t, engine.ShortBreak)
	a.StartNewCycle()
	rec.last(t, engine.Work)
	a.SkipToday()
	rec.last(t, engine.Idle)
	a.Start()
	a.Stop()
	rec.last(t, engine.Idle)
	if got := rec.count(); got != 9 {
		t.Fatalf("expected 9 transitions, got %d: %v", got, rec.seen)
	}
}

func TestOnTransitionFiresBeforeOnChange(t *testing.T) {
	var order []string
	var mu sync.Mutex
	a := New(minutes(25, 5, 15, 4))
	a.SetOnTransition(func(engine.State) { mu.Lock(); order = append(order, "transition"); mu.Unlock() })
	a.SetOnChange(func() { mu.Lock(); order = append(order, "change"); mu.Unlock() })
	a.Start()
	mu.Lock()
	defer mu.Unlock()
	if len(order) != 2 || order[0] != "transition" || order[1] != "change" {
		t.Fatalf("expected transition then change, got %v", order)
	}
}

func TestOnTransitionFiresWhenCountdownCompletes(t *testing.T) {
	rec := &transitionRecorder{}
	a := New(minutes(25, 5, 15, 4))
	clk := newFakeClock(time.Now())
	a.setClock(clk)
	a.SetOnTransition(rec.record)
	a.Start()
	clk.Advance(25 * time.Minute)
	rec.last(t, engine.AwaitingConfirm)
}

func TestOnTransitionFiresOnRestore(t *testing.T) {
	rec := &transitionRecorder{}
	a := New(minutes(25, 5, 15, 4))
	a.SetOnTransition(rec.record)
	snap := Snapshot{Engine: engine.Snapshot{State: engine.AwaitingConfirm, LastPhase: engine.Work}}
	if err := a.Restore(snap, time.Now()); err != nil {
		t.Fatalf(fmtRestore, err)
	}
	rec.last(t, engine.AwaitingConfirm)
	a.Stop()
}

func TestOnTransitionSilentForRefusedPauseAndAdvanceDay(t *testing.T) {
	rec := &transitionRecorder{}
	a := New(minutes(25, 5, 15, 4))
	a.SetOnTransition(rec.record)
	if a.Pause() {
		t.Fatal("expected pause to be refused while idle")
	}
	a.AdvanceDay(time.Now())
	a.Start()
	a.CompletePeriod()
	before := rec.count()
	if before != 2 {
		t.Fatalf("expected exactly Start and CompletePeriod to fire, got %d", before)
	}
	a.Stop()
}

func TestOnTransitionRunsUnderTimerLock(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	locked := make(chan bool, 1)
	a.SetOnTransition(func(engine.State) {
		// TryLock fails while the verb still holds the lock, which is the contract.
		locked <- !a.mu.TryLock()
	})
	a.Start()
	if !<-locked {
		t.Fatal("expected the transition hook to run while the Timer lock is held")
	}
}

func TestNewTakesOnlyDurations(t *testing.T) {
	a := New(minutes(25, 5, 15, 4))
	if got := a.State(); got != engine.Idle {
		t.Fatalf("expected Idle, got %s", got)
	}
}
