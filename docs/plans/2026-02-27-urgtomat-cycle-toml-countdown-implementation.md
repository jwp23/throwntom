# Urgtomat Cycle, TOML, and Countdown Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add configurable 25/5 with every-4th long break cadence, TOML config, and live `MM:SS` terminal countdown with daily completion tracking reset on first start.

**Architecture:** Extend the engine state machine with short/long break cadence and daily counters, migrate config loading to a constrained stdlib-only TOML parser, and add a countdown renderer in app/daemon orchestration. Keep notifier/scheduler boundaries unchanged and preserve reminder repeat-until-confirm behavior.

**Tech Stack:** Go (stdlib only), `go test`, `go build`, CLI daemon.

---

### Task 1: Expand config model for cycle cadence fields

**Files:**
- Modify: `internal/config/config.go`
- Modify: `internal/config/config_test.go`

**Step 1: Write the failing test**

```go
func TestDefaultCycleCadence(t *testing.T) {
	cfg := Default()
	if cfg.WorkMinutes != 25 || cfg.ShortBreakMinutes != 5 || cfg.LongBreakMinutes != 15 || cfg.LongBreakEvery != 4 {
		t.Fatalf("unexpected defaults: %+v", cfg)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test ./internal/config -run TestDefaultCycleCadence -v`  
Expected: FAIL because new fields do not exist.

**Step 3: Write minimal implementation**

Add fields to `Config`:

```go
WorkMinutes       int
ShortBreakMinutes int
LongBreakMinutes  int
LongBreakEvery    int
```

Set defaults:
- `WorkMinutes = 25`
- `ShortBreakMinutes = 5`
- `LongBreakMinutes = 15`
- `LongBreakEvery = 4`

**Step 4: Run test to verify it passes**

Run: `go test ./internal/config -run TestDefaultCycleCadence -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/config/config.go internal/config/config_test.go
git commit -m "feat: add cycle cadence fields to config defaults"
```

### Task 2: Replace JSON config parsing with constrained TOML parser

**Files:**
- Modify: `internal/config/config.go`
- Modify: `internal/config/config_test.go`

**Step 1: Write the failing test**

```go
func TestLoadBytesParsesToml(t *testing.T) {
	raw := []byte(`
work_minutes = 30
short_break_minutes = 6
long_break_minutes = 20
long_break_every = 3
repeat_secs = 15
schedule_time = "09:45"
schedule_days = ["Mon","Tue","Wed"]
`)
	cfg, err := LoadBytes(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.LongBreakEvery != 3 || cfg.Schedule.Time != "09:45" {
		t.Fatalf("unexpected parsed config: %+v", cfg)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test ./internal/config -run TestLoadBytesParsesToml -v`  
Expected: FAIL because loader still expects JSON.

**Step 3: Write minimal implementation**

Implement stdlib-only constrained TOML parsing:
- key/value lines split on first `=`
- integer parsing for numeric fields
- quoted string parsing for `schedule_time`
- string array parsing for `schedule_days`
- skip blank lines and comment lines beginning with `#`

Validate:
- positive durations/repeat
- `LongBreakEvery > 0`
- valid `HH:MM`
- non-empty days

**Step 4: Run test to verify it passes**

Run: `go test ./internal/config -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/config/config.go internal/config/config_test.go
git commit -m "feat: migrate config loader to constrained toml format"
```

### Task 3: Extend engine for short/long break cadence

**Files:**
- Modify: `internal/engine/engine.go`
- Modify: `internal/engine/engine_test.go`

**Step 1: Write the failing test**

```go
func TestEveryFourthWorkGoesToLongBreak(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork()
	for i := 0; i < 3; i++ {
		e.MarkPeriodComplete()
		e.ConfirmNext() // short break
		e.MarkPeriodComplete()
		e.ConfirmNext() // back to work
	}
	e.MarkPeriodComplete()
	e.ConfirmNext()
	if e.State() != LongBreak {
		t.Fatalf("expected LongBreak, got %v", e.State())
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test ./internal/engine -run TestEveryFourthWorkGoesToLongBreak -v`  
Expected: FAIL due to missing long break state/constructor.

**Step 3: Write minimal implementation**

Add:
- states: `ShortBreak`, `LongBreak`
- constructor signature: `New(workMin, shortBreakMin, longBreakMin, longBreakEvery int)`
- cadence counter: completed work sessions in block
- break selection in `ConfirmNext`

**Step 4: Run test to verify it passes**

Run: `go test ./internal/engine -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/engine/engine.go internal/engine/engine_test.go
git commit -m "feat: implement short and long break cadence in engine"
```

### Task 4: Add daily completed counter with reset-on-first-start

**Files:**
- Modify: `internal/engine/engine.go`
- Modify: `internal/engine/engine_test.go`

**Step 1: Write the failing test**

```go
func TestCompletedTodayResetsOnFirstStart(t *testing.T) {
	e := New(25, 5, 15, 4)
	e.StartWork() // first start of day
	e.MarkPeriodComplete()
	if e.CompletedToday() != 1 {
		t.Fatalf("expected completedToday=1")
	}
	e.SkipToday()
	e.StartWork() // first start of next work day
	if e.CompletedToday() != 0 {
		t.Fatalf("expected reset on first start, got %d", e.CompletedToday())
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test ./internal/engine -run TestCompletedTodayResetsOnFirstStart -v`  
Expected: FAIL because counter/reset API not present.

**Step 3: Write minimal implementation**

Add engine fields/methods:
- `completedToday int`
- `workDayStarted bool`
- `CompletedToday() int`

Behavior:
- on first `StartWork` when `workDayStarted=false`, reset `completedToday=0`, set `workDayStarted=true`
- increment `completedToday` when work period completes
- on `SkipToday`, set `workDayStarted=false`

**Step 4: Run test to verify it passes**

Run: `go test ./internal/engine -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/engine/engine.go internal/engine/engine_test.go
git commit -m "feat: add daily completion counter reset on first start"
```

### Task 5: Add countdown and session progress rendering in app

**Files:**
- Modify: `internal/app/app.go`
- Modify: `internal/app/app_test.go`

**Step 1: Write the failing test**

```go
func TestCountdownFormatMMSS(t *testing.T) {
	got := formatRemaining(9*time.Minute + 5*time.Second)
	if got != "09:05" {
		t.Fatalf("expected 09:05, got %s", got)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test ./internal/app -run TestCountdownFormatMMSS -v`  
Expected: FAIL because formatter/render helper does not exist.

**Step 3: Write minimal implementation**

Add:
- `phaseEndAt time.Time`
- countdown helper formatting `MM:SS`
- render method returning single-line status with:
  - phase
  - remaining/pending
  - completed today
  - work session index (for example `2/4`)

Ensure countdown is paused in awaiting-confirm mode.

**Step 4: Run test to verify it passes**

Run: `go test ./internal/app -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/app/app.go internal/app/app_test.go
git commit -m "feat: add countdown formatting and progress rendering"
```

### Task 6: Wire daemon output to live single-line countdown

**Files:**
- Modify: `cmd/urgtomat/main.go`
- Modify: `internal/app/app.go`
- Modify: `internal/app/app_test.go`

**Step 1: Write the failing test**

```go
func TestStatusLineShowsPendingWhenAwaitingConfirm(t *testing.T) {
	// use app test helpers to force awaiting-confirm state
	line := app.StatusLineForTest(...)
	if !strings.Contains(line, "transition pending") {
		t.Fatalf("expected pending line, got %s", line)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test ./internal/app -run TestStatusLineShowsPendingWhenAwaitingConfirm -v`  
Expected: FAIL because status-line helper does not include pending mode.

**Step 3: Write minimal implementation**

In daemon:
- run renderer goroutine with 1-second tick
- print `\r` plus status line, flush output
- keep prompt/command flow usable
- print startup line showing active cadence settings from config

In app:
- expose status-line method used by daemon and tests

**Step 4: Run test to verify it passes**

Run: `go test ./internal/app -v && go test ./cmd/urgtomat -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add cmd/urgtomat/main.go internal/app/app.go internal/app/app_test.go
git commit -m "feat: render live single-line countdown in daemon"
```

### Task 7: Update CLI long-flag help text and docs

**Files:**
- Modify: `cmd/urgtomat/main.go`
- Modify: `README.md`

**Step 1: Write the failing test**

No code test file required; define verification checks:
- usage/help text contains `--config`
- docs examples use `--config`

**Step 2: Run verification command (pre-change)**

Run: `go run ./cmd/urgtomat --help`  
Expected: current output may still show single dash usage strings.

**Step 3: Write minimal implementation**

Update usage text and docs examples:
- `urgtomat --config ./urgtomat.toml daemon`
- TOML example block (replace JSON example)

**Step 4: Run verification command**

Run:
- `go run ./cmd/urgtomat --help`
- `go test ./...`

Expected:
- help output displays `--config`
- tests pass.

**Step 5: Commit**

```bash
git add cmd/urgtomat/main.go README.md
git commit -m "docs: show double-dash config flag and toml examples"
```

### Task 8: End-to-end verification and smoke checks

**Files:**
- Modify: `README.md` (if needed for final command accuracy)

**Step 1: Run full test suite**

Run: `go test ./... -v`  
Expected: PASS.

**Step 2: Build binary**

Run: `go build ./cmd/urgtomat`  
Expected: success with no compilation warnings introduced.

**Step 3: Smoke run with temporary TOML config**

Run:

```bash
cat > /tmp/urgtomat.toml <<'EOF'
work_minutes = 25
short_break_minutes = 5
long_break_minutes = 15
long_break_every = 4
repeat_secs = 20
schedule_time = "09:15"
schedule_days = ["Mon","Tue","Wed","Thu","Fri"]
EOF
go run ./cmd/urgtomat --config /tmp/urgtomat.toml daemon
```

Expected:
- startup shows active cadence settings
- countdown/status line appears
- command prompt remains interactive.

**Step 4: Finalize docs**

Ensure `README.md` command examples match actual behavior exactly.

**Step 5: Commit**

```bash
git add README.md
git commit -m "chore: finalize verification and docs for cycle toml countdown update"
```
