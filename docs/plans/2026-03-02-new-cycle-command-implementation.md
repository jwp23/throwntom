# New Cycle Command Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `new-cycle` daemon command that immediately starts a new work session, resets cycle block progress, and preserves today's total completed pomodoros.

**Architecture:** Add a dedicated engine method that resets only block progress and transitions to work. Add an app-level orchestration method that stops reminder/timer state before starting a fresh work timer through the engine method. Expose the behavior through a new daemon command handler and update command/help documentation tests.

**Tech Stack:** Go standard library, existing internal packages (`engine`, `app`, daemon command routing), Go testing package.

---

### Task 1: Engine new-cycle behavior

**Files:**
- Modify: `internal/engine/engine_test.go`
- Modify: `internal/engine/engine.go`

**Step 1: Write the failing test**

```go
func TestStartNewCycleResetsBlockButPreservesCompletedToday(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	e.MarkPeriodComplete()
	e.ConfirmNext()
	e.MarkPeriodComplete()
	if e.CompletedToday() != 2 {
		t.Fatalf("expected completedToday=2 before reset, got %d", e.CompletedToday())
	}

	e.StartNewCycle()

	if e.State() != Work {
		t.Fatalf("expected Work after new cycle, got %v", e.State())
	}
	if e.WorkSessionsInBlock() != 0 {
		t.Fatalf("expected block progress reset, got %d", e.WorkSessionsInBlock())
	}
	if e.CompletedToday() != 2 {
		t.Fatalf("expected completedToday preserved, got %d", e.CompletedToday())
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s ./internal/engine -run TestStartNewCycleResetsBlockButPreservesCompletedToday -v`
Expected: FAIL because `StartNewCycle` does not exist.

**Step 3: Write minimal implementation**

```go
func (e *Engine) StartNewCycle() {
	e.workDayStarted = true
	e.workSessionsBlock = 0
	e.state = Work
	e.lastPhase = Work
	e.pausedFrom = Idle
}
```

**Step 4: Run test to verify it passes**

Run: `go test -timeout 30s ./internal/engine -run TestStartNewCycleResetsBlockButPreservesCompletedToday -v`
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/engine/engine.go internal/engine/engine_test.go
git commit -m "feat(engine): add new cycle start behavior"
```

### Task 2: App orchestration for new cycle

**Files:**
- Modify: `internal/app/app_test.go`
- Modify: `internal/app/app.go`

**Step 1: Write the failing test**

```go
func TestStartNewCycleResetsCycleProgressButPreservesDailyTotal(t *testing.T) {
	n := &fakeNotifier{}
	a := NewForTest(25, 5, 15, 4, 20*time.Millisecond, n)
	a.Start()
	a.CompletePeriod()
	if !strings.Contains(a.StatusLine(), "today's pomodoros=1") {
		t.Fatalf("expected daily total before reset")
	}

	a.StartNewCycle()
	line := a.StatusLine()
	if !strings.Contains(line, "pomodoro") || !strings.Contains(line, "pomodoros=0/4") {
		t.Fatalf("expected new cycle progress reset, got %s", line)
	}
	if !strings.Contains(line, "today's pomodoros=1") {
		t.Fatalf("expected daily total preserved, got %s", line)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s ./internal/app -run TestStartNewCycleResetsCycleProgressButPreservesDailyTotal -v`
Expected: FAIL because `StartNewCycle` is missing in `App`.

**Step 3: Write minimal implementation**

```go
func (a *App) StartNewCycle() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.stopReminderLocked()
	a.stopTimerLocked()
	a.phaseEndAt = time.Time{}
	a.pausedRemaining = 0
	a.engine.StartNewCycle()
	a.startPhaseTimerLocked(a.workDuration)
}
```

**Step 4: Run test to verify it passes**

Run: `go test -timeout 30s ./internal/app -run TestStartNewCycleResetsCycleProgressButPreservesDailyTotal -v`
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/app/app.go internal/app/app_test.go
git commit -m "feat(app): add new cycle orchestration"
```

### Task 3: Daemon command wiring and command documentation

**Files:**
- Modify: `cmd/throwntom/daemon_core_test.go`
- Modify: `cmd/throwntom/main_test.go`
- Modify: `cmd/throwntom/daemon_core.go`
- Modify: `README.md`
- Modify: `cmd/throwntom/readme_test.go`

**Step 1: Write failing tests**

```go
func TestNewCycleCommandResetsCycleProgressButKeepsDailyTotal(t *testing.T) {
	cfg := config.Default()
	cfg.MorningReminderPending = false
	core := newDaemonCore(cfg, noopNotifier{})

	core.execute("start")
	core.cycle.CompletePeriod()
	before, _ := core.snapshot()
	if !strings.Contains(before, "today's pomodoros=1") {
		t.Fatalf("expected baseline daily total, got %s", before)
	}

	result := core.execute("new-cycle")
	after, _ := core.snapshot()
	if result.err != nil {
		t.Fatalf("new-cycle command failed: %v", result.err)
	}
	if !strings.Contains(after, "pomodoro") || !strings.Contains(after, "pomodoros=0/4") {
		t.Fatalf("expected reset cycle progress, got %s", after)
	}
	if !strings.Contains(after, "today's pomodoros=1") {
		t.Fatalf("expected preserved daily total, got %s", after)
	}
}
```

Also update command-help/readme tests to require `new-cycle`.

**Step 2: Run tests to verify failures**

Run:
- `go test -timeout 30s ./cmd/throwntom -run TestNewCycleCommandResetsCycleProgressButKeepsDailyTotal -v`
- `go test -timeout 30s ./cmd/throwntom -run TestDaemonCommandHelpIncludesNewControls -v`
- `go test -timeout 30s ./cmd/throwntom -run TestREADMEIncludesInstallAndDaemonCommands -v`

Expected: FAIL because command/help/docs are missing `new-cycle`.

**Step 3: Write minimal implementation**

- Add `new-cycle` handler in command map.
- Implement handler to call `d.state.stopMorningLoop()`, `d.state.clearSnooze()`, and `d.cycle.StartNewCycle()`.
- Return message like `new pomodoro cycle started`.
- Update daemon command help string and README daemon command list.

**Step 4: Run tests to verify pass**

Run: `go test -timeout 30s ./cmd/throwntom -v`
Expected: PASS.

**Step 5: Commit**

```bash
git add cmd/throwntom/daemon_core.go cmd/throwntom/daemon_core_test.go cmd/throwntom/main_test.go README.md cmd/throwntom/readme_test.go
git commit -m "feat(daemon): add new-cycle command"
```

### Task 4: Full verification

**Files:**
- No source changes required

**Step 1: Run full test suite**

Run: `go test -timeout 30s ./...`
Expected: PASS with no warnings.

**Step 2: Verify clean working tree**

Run: `git status -sb`
Expected: clean branch state.
