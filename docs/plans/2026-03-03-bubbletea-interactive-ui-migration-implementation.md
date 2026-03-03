# Bubble Tea Interactive UI Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the custom raw-terminal interactive loop with Bubble Tea while preserving existing command behavior and eliminating resize/input redraw regressions.

**Architecture:** Keep daemon/domain logic untouched and migrate only the terminal interaction boundary in `cmd/throwntom`. Introduce a Bubble Tea model that owns prompt state, status/message rendering, and periodic refresh, then wire existing `StatusSnapshot`/`Execute` callbacks into that model. Remove legacy ANSI/raw-mode code after parity tests pass.

**Tech Stack:** Go 1.25, `github.com/charmbracelet/bubbletea`, existing `cmd/throwntom` callbacks/tests, `go test -timeout 30s`.

---

### Task 1: Add Bubble Tea Model RED Tests

**Files:**
- Create: `cmd/throwntom/interactive_tea_model_test.go`

**Step 1: Write failing unit tests for model key/tick/resize behavior**

```go
package main

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestTeaModelPrintableBackspaceAndEnter(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, bool) { return "idle | 00:00", false },
		Execute: func(command string) (daemonControlResponse, error) {
			return daemonControlResponse{
				StatusLine:     "idle | 00:00",
				MorningPending: false,
				Message:        "ok",
				Exit:           command == "quit",
			}, nil
		},
	})

	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'s'}})
	next, _ = next.(interactiveTeaModel).Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'t'}})
	next, _ = next.(interactiveTeaModel).Update(tea.KeyMsg{Type: tea.KeyBackspace})
	next, _ = next.(interactiveTeaModel).Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'a'}})
	next, _ = next.(interactiveTeaModel).Update(tea.KeyMsg{Type: tea.KeyEnter})

	got := next.(interactiveTeaModel).View()
	if want := "command> "; !containsLinePrefix(got, want) {
		t.Fatalf("expected cleared prompt after submit, view=%q", got)
	}
	if want := "message: ok"; !containsLinePrefix(got, want) {
		t.Fatalf("expected message line %q, view=%q", want, got)
	}
}

func TestTeaModelTickRefreshesStatusAndKeepsPrompt(t *testing.T) {
	count := 0
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, bool) {
			count++
			return "idle | 00:0" + string(rune('0'+count)), false
		},
		Execute: func(string) (daemonControlResponse, error) { return daemonControlResponse{}, nil },
	})

	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'s'}})
	next, _ = next.(interactiveTeaModel).Update(interactiveTickMsg{})

	got := next.(interactiveTeaModel).View()
	if want := "command> s"; !containsLinePrefix(got, want) {
		t.Fatalf("expected prompt to persist across tick, view=%q", got)
	}
}

func TestTeaModelWindowSizeClampsView(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00 | today's pomodoros=0 | pomodoros=0/4", false
		},
		Execute: func(string) (daemonControlResponse, error) { return daemonControlResponse{}, nil },
	})

	next, _ := model.Update(tea.WindowSizeMsg{Width: 20, Height: 24})
	for _, line := range splitLines(next.(interactiveTeaModel).View()) {
		if len([]rune(line)) > 20 {
			t.Fatalf("line exceeds width clamp: %q", line)
		}
	}
}
```

**Step 2: Run test to verify RED state**

Run: `go test -timeout 30s ./cmd/throwntom -run 'TestTeaModelPrintableBackspaceAndEnter|TestTeaModelTickRefreshesStatusAndKeepsPrompt|TestTeaModelWindowSizeClampsView' -v`

Expected: FAIL because `newInteractiveTeaModel`, `interactiveTeaModel`, and tick helpers do not exist.

**Step 3: Commit failing tests (RED checkpoint)**

```bash
git add cmd/throwntom/interactive_tea_model_test.go
git commit -m "test: add red tests for bubbletea interactive model"
```

### Task 2: Implement Bubble Tea Model (GREEN)

**Files:**
- Create: `cmd/throwntom/interactive_tea_model.go`
- Modify: `cmd/throwntom/terminal_ui.go`
- Modify: `cmd/throwntom/terminal_ui_test.go`

**Step 1: Implement minimal Bubble Tea model and render helpers**

```go
package main

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

type interactiveTickMsg struct{}

type interactiveTeaModel struct {
	callbacks       interactiveCallbacks
	statusLine      string
	morningPending  bool
	message         string
	prompt          promptState
	width           int
	quitRequested   bool
}

func newInteractiveTeaModel(callbacks interactiveCallbacks) interactiveTeaModel {
	statusLine, morningPending := callbacks.StatusSnapshot()
	return interactiveTeaModel{
		callbacks:      callbacks,
		statusLine:     statusLine,
		morningPending: morningPending,
	}
}

func (m interactiveTeaModel) Init() tea.Cmd { return interactiveTickCmd() }

func interactiveTickCmd() tea.Cmd {
	return tea.Tick(time.Second, func(time.Time) tea.Msg { return interactiveTickMsg{} })
}

func (m interactiveTeaModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return updateModelWithKey(m, msg)
	case interactiveTickMsg:
		m.statusLine, m.morningPending = m.callbacks.StatusSnapshot()
		return m, interactiveTickCmd()
	case tea.WindowSizeMsg:
		m.width = msg.Width
		return m, nil
	default:
		return m, nil
	}
}

func (m interactiveTeaModel) View() string {
	return renderFrameWithWidth(m.statusLine, m.morningPending, m.message, m.prompt.input, m.width)
}
```

**Step 2: Add helper assertions used by tests**

```go
func containsLinePrefix(view string, prefix string) bool {
	for _, line := range splitLines(view) {
		if strings.HasPrefix(line, prefix) {
			return true
		}
	}
	return false
}
```

**Step 3: Run GREEN command for Task 1 tests**

Run: `go test -timeout 30s ./cmd/throwntom -run 'TestTeaModelPrintableBackspaceAndEnter|TestTeaModelTickRefreshesStatusAndKeepsPrompt|TestTeaModelWindowSizeClampsView' -v`

Expected: PASS.

**Step 4: Commit GREEN implementation**

```bash
git add cmd/throwntom/interactive_tea_model.go cmd/throwntom/interactive_tea_model_test.go cmd/throwntom/terminal_ui.go cmd/throwntom/terminal_ui_test.go
git commit -m "feat: add bubbletea model for interactive ui"
```

### Task 3: Add Program Runner Adapter (RED/GREEN)

**Files:**
- Create: `cmd/throwntom/interactive_tea_program.go`
- Create: `cmd/throwntom/interactive_tea_program_test.go`
- Modify: `go.mod`

**Step 1: Add RED tests for callback validation and ctrl-c exit behavior**

```go
func TestRunInteractiveTeaRequiresCallbacks(t *testing.T) {
	var out bytes.Buffer
	err := runInteractiveTea(&out, strings.NewReader(""), interactiveCallbacks{})
	if err == nil || !strings.Contains(err.Error(), "interactive callbacks must provide status snapshot and execute handlers") {
		t.Fatalf("expected callback validation error, got %v", err)
	}
}

func TestRunInteractiveTeaCtrlCExitsWithoutExecute(t *testing.T) {
	var out bytes.Buffer
	executed := false
	err := runInteractiveTea(
		&out,
		strings.NewReader("\x03"),
		interactiveCallbacks{
			StatusSnapshot: func() (string, bool) { return "idle | 00:00", false },
			Execute: func(string) (daemonControlResponse, error) {
				executed = true
				return daemonControlResponse{}, nil
			},
		},
	)
	if err != nil {
		t.Fatalf("runInteractiveTea returned error: %v", err)
	}
	if executed {
		t.Fatal("expected ctrl-c to exit without Execute callback")
	}
}
```

**Step 2: Run RED command**

Run: `go test -timeout 30s ./cmd/throwntom -run 'TestRunInteractiveTeaRequiresCallbacks|TestRunInteractiveTeaCtrlCExitsWithoutExecute' -v`

Expected: FAIL because `runInteractiveTea` does not exist.

**Step 3: Add Bubble Tea dependency and implement adapter**

```go
func runInteractiveTea(out io.Writer, in io.Reader, callbacks interactiveCallbacks) error {
	if callbacks.StatusSnapshot == nil || callbacks.Execute == nil {
		return fmt.Errorf("interactive callbacks must provide status snapshot and execute handlers")
	}

	model := newInteractiveTeaModel(callbacks)
	program := tea.NewProgram(
		model,
		tea.WithInput(in),
		tea.WithOutput(out),
	)
	_, err := program.Run()
	return err
}
```

Dependency command:
- `go get github.com/charmbracelet/bubbletea@latest`

**Step 4: Run GREEN command**

Run: `go test -timeout 30s ./cmd/throwntom -run 'TestRunInteractiveTeaRequiresCallbacks|TestRunInteractiveTeaCtrlCExitsWithoutExecute' -v`

Expected: PASS.

**Step 5: Commit**

```bash
git add go.mod go.sum cmd/throwntom/interactive_tea_program.go cmd/throwntom/interactive_tea_program_test.go
git commit -m "feat: add bubbletea program adapter for interactive mode"
```

### Task 4: Wire Run/Shell Modes to Bubble Tea (RED/GREEN)

**Files:**
- Modify: `cmd/throwntom/modes.go`
- Create: `cmd/throwntom/modes_bubbletea_test.go`

**Step 1: Write RED tests for mode wiring**

```go
func TestRunLocalModeUsesInteractiveTea(t *testing.T) {
	// Use injected function var runInteractiveUI to assert invocation.
	// Fail until modes.go routes through new adapter seam.
}

func TestRunShellModeUsesInteractiveTea(t *testing.T) {
	// Same seam assertion for shell mode path.
}
```

**Step 2: Run RED command**

Run: `go test -timeout 30s ./cmd/throwntom -run 'TestRunLocalModeUsesInteractiveTea|TestRunShellModeUsesInteractiveTea' -v`

Expected: FAIL because injection seam and Bubble Tea wiring are absent.

**Step 3: Implement minimal wiring seam**

```go
var runInteractiveUI = runInteractiveTea

// in runLocalMode / runShellMode:
err = runInteractiveUI(os.Stdout, os.Stdin, interactiveCallbacks{
	StatusSnapshot: ...,
	Execute: ...,
})
```

**Step 4: Run GREEN command**

Run: `go test -timeout 30s ./cmd/throwntom -run 'TestRunLocalModeUsesInteractiveTea|TestRunShellModeUsesInteractiveTea' -v`

Expected: PASS.

**Step 5: Commit**

```bash
git add cmd/throwntom/modes.go cmd/throwntom/modes_bubbletea_test.go
git commit -m "refactor: route interactive modes through bubbletea adapter"
```

### Task 5: Remove Legacy Raw ANSI Loop (RED/GREEN)

**Files:**
- Delete: `cmd/throwntom/interactive_loop.go`
- Delete: `cmd/throwntom/interactive_loop_test.go`
- Delete: `cmd/throwntom/terminal_input_unix.go`
- Delete: `cmd/throwntom/terminal_input_ioctl_darwin.go`
- Delete: `cmd/throwntom/terminal_input_ioctl_linux.go`
- Delete: `cmd/throwntom/terminal_input_test.go`
- Modify: `cmd/throwntom/terminal_ui.go`
- Modify: `cmd/throwntom/terminal_ui_test.go`

**Step 1: Add RED tests asserting the retained 3-line contract through Bubble Tea model view**

```go
func TestInteractiveTeaViewHasThreeLines(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, bool) { return "idle | 00:00", false },
		Execute: func(string) (daemonControlResponse, error) { return daemonControlResponse{}, nil },
	})
	lines := splitLines(model.View())
	if len(lines) != 3 {
		t.Fatalf("expected 3 lines, got %d", len(lines))
	}
}
```

**Step 2: Run RED command**

Run: `go test -timeout 30s ./cmd/throwntom -run 'TestInteractiveTeaViewHasThreeLines' -v`

Expected: FAIL before cleanup if helpers are still tied to removed raw-loop internals.

**Step 3: Remove legacy files and prune unused functions**

Minimal cleanup target:
- keep `renderFrameWithWidth` and `clampTerminalLine`
- drop `renderFullFrameWithWidth` and ANSI-anchor behavior no longer needed
- remove dead raw-input helpers

**Step 4: Run GREEN command for package**

Run: `go test -timeout 30s ./cmd/throwntom -v`

Expected: PASS with no compile warnings.

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove legacy raw terminal interactive loop"
```

### Task 6: Add Resize Regression Smoke Test to E2E Suite (RED/GREEN)

**Files:**
- Modify: `e2e/daemon_e2e_test.go`

**Step 1: Add RED e2e smoke test (skip when `script` command unavailable)**

```go
func TestInteractiveResizeSmokeNoLineClobber(t *testing.T) {
	if _, err := exec.LookPath("script"); err != nil {
		t.Skip("script command not available")
	}

	bin := buildBinary(t)
	cmd := exec.Command(
		"script", "-q", "/dev/null",
		"sh", "-c",
		`(sleep 0.2; stty cols 40; sleep 0.2; stty cols 120) & exec "$1"`,
		"sh", bin,
	)
	cmd.Stdin = strings.NewReader("status\nquit\n")
	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &out

	err := cmd.Run()
	if err != nil {
		t.Fatalf("interactive smoke failed: %v\n%s", err, out.String())
	}

	if strings.Contains(out.String(), "\x1b[3F") {
		t.Fatalf("expected no legacy ANSI anchor sequence, got output %q", out.String())
	}
	if !strings.Contains(out.String(), "command> ") {
		t.Fatalf("expected prompt in output, got %q", out.String())
	}
	if !strings.Contains(out.String(), "status:") {
		t.Fatalf("expected status line in output, got %q", out.String())
	}
}
```

**Step 2: Run RED command**

Run: `go test -timeout 30s -tags=e2e ./e2e -run TestInteractiveResizeSmokeNoLineClobber -v`

Expected: FAIL before Bubble Tea migration lands.

**Step 3: Finalize stdlib-only test command and assertion set**

Assert:
- command prompt appears
- no legacy ANSI cursor-anchor sequence
- command output includes `status:`

**Step 4: Run GREEN command**

Run: `go test -timeout 30s -tags=e2e ./e2e -run TestInteractiveResizeSmokeNoLineClobber -v`

Expected: PASS (or SKIP when `script` absent).

**Step 5: Commit**

```bash
git add e2e/daemon_e2e_test.go
git commit -m "test: add e2e smoke test for interactive resize regression"
```

### Task 7: Full Verification and Docs Sync

**Files:**
- Modify: `README.md`

**Step 1: Update README interactive UI notes**

Add a short note in `README.md` that interactive terminal behavior is managed by Bubble Tea and remains 3-line command/status/message driven.

**Step 2: Run full verification**

Run:
- `go test -timeout 30s ./...`
- `go test -timeout 30s -tags=e2e ./e2e`
- `go vet ./...`

Expected: PASS (e2e resize smoke may SKIP if `script` unavailable).

**Step 3: Commit final docs update**

```bash
git add README.md
git commit -m "docs: document bubbletea interactive runtime"
```
