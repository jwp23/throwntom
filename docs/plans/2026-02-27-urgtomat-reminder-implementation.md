# Urgtomat Reminder CLI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS-first CLI urgtomat daemon that repeats sound reminders until confirmation and supports configurable morning start reminders.

**Architecture:** Implement a platform-agnostic core (`engine`, `scheduler`, `reminder`, `config`) plus a small `notifier` adapter package with a macOS implementation first. Keep OS-specific behavior behind interfaces so Linux support is an adapter add-on. Drive development with focused unit tests and small commits.

**Tech Stack:** Go (stdlib only), `go test`, CLI binary, local JSON config.

---

### Task 1: Bootstrap module and config model

**Files:**
- Create: `go.mod`
- Create: `cmd/urgtomat/main.go`
- Create: `internal/config/config.go`
- Create: `internal/config/config_test.go`

**Step 1: Write the failing test**

```go
package config

import "testing"

func TestDefaultConfig(t *testing.T) {
	cfg := Default()
	if cfg.Schedule.Time != "09:15" {
		t.Fatalf("expected default time 09:15, got %s", cfg.Schedule.Time)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `timeout 30 go test ./internal/config -run TestDefaultConfig -v`  
Expected: FAIL with missing `Default`.

**Step 3: Write minimal implementation**

```go
type Config struct {
	Schedule struct {
		Days []string `json:"days"`
		Time string   `json:"time"`
	} `json:"schedule"`
	WorkMinutes  int `json:"work_minutes"`
	BreakMinutes int `json:"break_minutes"`
	RepeatSecs   int `json:"repeat_secs"`
}

func Default() Config {
	var cfg Config
	cfg.Schedule.Days = []string{"Mon", "Tue", "Wed", "Thu", "Fri"}
	cfg.Schedule.Time = "09:15"
	cfg.WorkMinutes = 25
	cfg.BreakMinutes = 5
	cfg.RepeatSecs = 20
	return cfg
}
```

**Step 4: Run test to verify it passes**

Run: `timeout 30 go test ./internal/config -run TestDefaultConfig -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add go.mod cmd/urgtomat/main.go internal/config/config.go internal/config/config_test.go
git commit -m "feat: bootstrap module and default config"
```

### Task 2: Add config file load + validation

**Files:**
- Modify: `internal/config/config.go`
- Modify: `internal/config/config_test.go`

**Step 1: Write the failing test**

```go
func TestLoadRejectsInvalidTime(t *testing.T) {
	_, err := LoadBytes([]byte(`{"schedule":{"days":["Mon"],"time":"9:15"}}`))
	if err == nil {
		t.Fatal("expected invalid time format error")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `timeout 30 go test ./internal/config -run TestLoadRejectsInvalidTime -v`  
Expected: FAIL because `LoadBytes` does not exist.

**Step 3: Write minimal implementation**

```go
func LoadBytes(b []byte) (Config, error) {
	cfg := Default()
	if len(b) > 0 {
		if err := json.Unmarshal(b, &cfg); err != nil {
			return Config{}, fmt.Errorf("parse config: %w", err)
		}
	}
	if err := validate(cfg); err != nil {
		return Config{}, err
	}
	return cfg, nil
}
```

Include `validate` checks for:
- time in strict `HH:MM`
- `WorkMinutes > 0`, `BreakMinutes > 0`
- `RepeatSecs > 0`

**Step 4: Run test to verify it passes**

Run: `timeout 30 go test ./internal/config -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/config/config.go internal/config/config_test.go
git commit -m "feat: add config loading and validation"
```

### Task 3: Implement urgtomat state machine

**Files:**
- Create: `internal/engine/engine.go`
- Create: `internal/engine/engine_test.go`

**Step 1: Write the failing test**

```go
func TestConfirmTransitionWorkToBreak(t *testing.T) {
	e := New(25, 5)
	e.StartWork()
	e.MarkPeriodComplete()
	if e.State() != AwaitingConfirm {
		t.Fatalf("expected AwaitingConfirm")
	}
	e.ConfirmNext()
	if e.State() != Break {
		t.Fatalf("expected Break")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `timeout 30 go test ./internal/engine -run TestConfirmTransitionWorkToBreak -v`  
Expected: FAIL with missing engine APIs.

**Step 3: Write minimal implementation**

```go
type State int

const (
	Idle State = iota
	Work
	Break
	AwaitingConfirm
	Paused
)
```

Add methods:
- `StartWork()`
- `MarkPeriodComplete()`
- `ConfirmNext()`
- `Snooze(d time.Duration)`
- `SkipToday()`

**Step 4: Run test to verify it passes**

Run: `timeout 30 go test ./internal/engine -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/engine/engine.go internal/engine/engine_test.go
git commit -m "feat: add urgtomat state machine with confirmation transitions"
```

### Task 4: Implement repeat-until-confirm reminder loop

**Files:**
- Create: `internal/reminder/loop.go`
- Create: `internal/reminder/loop_test.go`

**Step 1: Write the failing test**

```go
func TestLoopRepeatsUntilAck(t *testing.T) {
	count := 0
	loop := New(20*time.Millisecond, func() error {
		count++
		return nil
	})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go loop.Run(ctx)
	time.Sleep(70 * time.Millisecond)
	loop.Ack()
	got := count
	time.Sleep(50 * time.Millisecond)
	if count != got {
		t.Fatalf("expected no more reminders after ack")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `timeout 30 go test ./internal/reminder -run TestLoopRepeatsUntilAck -v`  
Expected: FAIL with missing loop implementation.

**Step 3: Write minimal implementation**

```go
type Loop struct {
	interval time.Duration
	notify   func() error
	acked    atomic.Bool
}
```

`Run` behavior:
- call `notify` immediately
- tick at interval while not acked
- stop on context cancel or `Ack`

**Step 4: Run test to verify it passes**

Run: `timeout 30 go test ./internal/reminder -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/reminder/loop.go internal/reminder/loop_test.go
git commit -m "feat: add repeating reminder loop"
```

### Task 5: Implement scheduler for weekday time windows

**Files:**
- Create: `internal/scheduler/scheduler.go`
- Create: `internal/scheduler/scheduler_test.go`

**Step 1: Write the failing test**

```go
func TestShouldTriggerMorningReminder(t *testing.T) {
	s := New([]string{"Mon", "Tue", "Wed", "Thu", "Fri"}, "09:15")
	at := time.Date(2026, 3, 2, 9, 15, 0, 0, time.Local) // Monday
	if !s.ShouldTrigger(at) {
		t.Fatal("expected trigger at scheduled weekday/time")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `timeout 30 go test ./internal/scheduler -run TestShouldTriggerMorningReminder -v`  
Expected: FAIL due to missing scheduler.

**Step 3: Write minimal implementation**

Implement:
- parsed weekday set
- parsed `HH:MM`
- `ShouldTrigger(now time.Time) bool`
- `NextTrigger(from time.Time) time.Time`

**Step 4: Run test to verify it passes**

Run: `timeout 30 go test ./internal/scheduler -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/scheduler/scheduler.go internal/scheduler/scheduler_test.go
git commit -m "feat: add weekday morning scheduler"
```

### Task 6: Add macOS notifier adapter

**Files:**
- Create: `internal/notifier/notifier.go`
- Create: `internal/notifier/macos.go`
- Create: `internal/notifier/notifier_test.go`

**Step 1: Write the failing test**

```go
func TestNotifierFallbackOnCommandError(t *testing.T) {
	n := NewTestNotifier(func(name string, args ...string) error {
		return errors.New("exec failed")
	})
	if err := n.PlaySound("default"); err == nil {
		t.Fatal("expected contextual error")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `timeout 30 go test ./internal/notifier -run TestNotifierFallbackOnCommandError -v`  
Expected: FAIL because notifier does not exist.

**Step 3: Write minimal implementation**

Define:
- interface `Notifier { PlaySound(name string) error }`
- macOS impl using `exec.Command("afplay", "/System/Library/Sounds/Glass.aiff")`
- fallback path returns contextual error; caller handles terminal bell fallback

**Step 4: Run test to verify it passes**

Run: `timeout 30 go test ./internal/notifier -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add internal/notifier/notifier.go internal/notifier/macos.go internal/notifier/notifier_test.go
git commit -m "feat: add macos sound notifier adapter"
```

### Task 7: Wire CLI commands and daemon loop

**Files:**
- Modify: `cmd/urgtomat/main.go`
- Create: `internal/app/app.go`
- Create: `internal/app/app_test.go`

**Step 1: Write the failing test**

```go
func TestStatusShowsAwaitingConfirm(t *testing.T) {
	app := NewForTest(...)
	app.TriggerTransitionReminder()
	status := app.Status()
	if !strings.Contains(status, "awaiting confirmation") {
		t.Fatalf("unexpected status: %s", status)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `timeout 30 go test ./internal/app -run TestStatusShowsAwaitingConfirm -v`  
Expected: FAIL due to missing app orchestration.

**Step 3: Write minimal implementation**

Implement command flow:
- `urgtomat daemon`
- `urgtomat start`
- `urgtomat confirm`
- `urgtomat snooze <duration>`
- `urgtomat skip-today`
- `urgtomat status`

Wire:
- scheduler trigger -> reminder loop -> explicit confirmation commands
- notifier errors -> terminal bell fallback

**Step 4: Run test to verify it passes**

Run: `timeout 30 go test ./... -v`  
Expected: PASS.

**Step 5: Commit**

```bash
git add cmd/urgtomat/main.go internal/app/app.go internal/app/app_test.go
git commit -m "feat: wire cli commands and daemon orchestration"
```

### Task 8: Add docs and smoke-test instructions

**Files:**
- Create: `README.md`

**Step 1: Write the failing test**

No code test. Define acceptance check: commands in README run without compile warnings.

**Step 2: Run verification before writing docs**

Run: `timeout 30 go test ./... -v`  
Expected: PASS.

**Step 3: Write minimal documentation**

Include:
- setup/build (`go build ./cmd/urgtomat`)
- config file example
- startup command (`urgtomat daemon`)
- control commands (`start`, `confirm`, `snooze`, `status`)
- note on macOS-only notifier in v1 and Linux adapter extension point

**Step 4: Run smoke checks**

Run:
- `timeout 30 go test ./... -v`
- `timeout 30 go build ./cmd/urgtomat`

Expected: both succeed with no warnings introduced.

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add usage and smoke-test instructions"
```
