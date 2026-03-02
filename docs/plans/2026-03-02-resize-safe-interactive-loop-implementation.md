# Resize-Safe Interactive Loop Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace scanner-based interactive input with a raw-input, resize-safe loop that keeps the 3-line UI stable and allows 1-second status redraw while idle at the prompt.

**Architecture:** Introduce a shared interactive loop that owns input buffer state, tick/resize redraw triggers, and frame rendering. Keep daemon logic and command semantics unchanged by injecting mode-specific callbacks for status snapshot and command execution. Use pure reducer-style helpers for key handling and event transitions to keep unit tests fast and deterministic.

**Tech Stack:** Go standard library (`time`, `os/signal`, `syscall`, `bufio`, `io`), existing `cmd/throwntom` packages, `go test`.

---

### Task 1: Add Prompt State Reducer (Pure Unit Layer)

**Files:**
- Create: `cmd/throwntom/interactive_model.go`
- Create: `cmd/throwntom/interactive_model_test.go`

**Step 1: Write the failing tests**

Add tests for buffer behavior and submit semantics:

```go
func TestApplyKeyPrintableAppendsRune(t *testing.T) {
	state := promptState{}
	state, submitted, ok := applyKey(state, keyEvent{kind: keyPrintable, r: 'a'})
	if !ok || submitted != "" || state.input != "a" {
		t.Fatalf("unexpected state: %+v submitted=%q ok=%t", state, submitted, ok)
	}
}

func TestApplyKeyBackspaceDeletesLastRune(t *testing.T) {
	state := promptState{input: "ab"}
	state, submitted, ok := applyKey(state, keyEvent{kind: keyBackspace})
	if !ok || submitted != "" || state.input != "a" {
		t.Fatalf("unexpected state: %+v submitted=%q ok=%t", state, submitted, ok)
	}
}

func TestApplyKeyEnterSubmitsAndClearsBuffer(t *testing.T) {
	state := promptState{input: "status"}
	state, submitted, ok := applyKey(state, keyEvent{kind: keyEnter})
	if !ok || submitted != "status" || state.input != "" {
		t.Fatalf("unexpected state: %+v submitted=%q ok=%t", state, submitted, ok)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s ./cmd/throwntom -run 'TestApplyKeyPrintableAppendsRune|TestApplyKeyBackspaceDeletesLastRune|TestApplyKeyEnterSubmitsAndClearsBuffer' -v`

Expected: FAIL because reducer types/functions do not exist yet.

**Step 3: Write minimal implementation**

Implement reducer primitives:

```go
type promptState struct { input string }

type keyKind int

const (
	keyPrintable keyKind = iota
	keyBackspace
	keyEnter
)

type keyEvent struct {
	kind keyKind
	r    rune
}

func applyKey(state promptState, ev keyEvent) (promptState, string, bool) {
	switch ev.kind {
	case keyPrintable:
		state.input += string(ev.r)
		return state, "", true
	case keyBackspace:
		r := []rune(state.input)
		if len(r) > 0 {
			state.input = string(r[:len(r)-1])
		}
		return state, "", true
	case keyEnter:
		submitted := state.input
		state.input = ""
		return state, submitted, true
	default:
		return state, "", false
	}
}
```

**Step 4: Run test to verify it passes**

Run same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add cmd/throwntom/interactive_model.go cmd/throwntom/interactive_model_test.go
git commit -m "test: add prompt input reducer tests"
```

### Task 2: Add Full-Frame 3-Line Renderer Contract

**Files:**
- Modify: `cmd/throwntom/terminal_ui_test.go`
- Modify: `cmd/throwntom/terminal_ui.go`

**Step 1: Write the failing tests**

Add renderer tests for deterministic full-frame redraw:

```go
func TestRenderFullFrameIncludesThreeLines(t *testing.T) {
	got := renderFullFrame("idle | 00:00", false, "waiting", "sta")
	if !strings.Contains(got, "status: idle | 00:00 morning reminder pending=false") {
		t.Fatalf("missing status line: %q", got)
	}
	if !strings.Contains(got, "\nmessage: waiting\n") {
		t.Fatalf("missing message line: %q", got)
	}
	if !strings.Contains(got, "\ncommand> sta") {
		t.Fatalf("missing prompt line: %q", got)
	}
}

func TestRenderFullFrameClearsAndReanchorsCursor(t *testing.T) {
	got := renderFullFrame("idle | 00:00", false, "", "")
	if !strings.HasPrefix(got, "\x1b[3F\x1b[J") {
		t.Fatalf("expected redraw anchor prefix, got %q", got)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s ./cmd/throwntom -run 'TestRenderFullFrameIncludesThreeLines|TestRenderFullFrameClearsAndReanchorsCursor' -v`

Expected: FAIL because `renderFullFrame` does not exist.

**Step 3: Write minimal implementation**

Implement full-frame renderer and wire `ShowFrame`/`UpdateStatus` to use it:

```go
func renderFullFrame(statusLine string, morningPending bool, message string, input string) string {
	return fmt.Sprintf(
		"\x1b[3F\x1b[Jstatus: %s morning reminder pending=%t\nmessage: %s\ncommand> %s",
		statusLine,
		morningPending,
		message,
		input,
	)
}
```

Keep existing behavior for first paint by emitting a baseline frame before redraw-prefix use (or conditionally skip prefix for first draw).

**Step 4: Run test to verify it passes**

Run same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add cmd/throwntom/terminal_ui.go cmd/throwntom/terminal_ui_test.go
git commit -m "refactor: render terminal ui with full-frame redraw"
```

### Task 3: Add Key Parsing + Raw Terminal Mode Primitives

**Files:**
- Create: `cmd/throwntom/terminal_input_unix.go`
- Create: `cmd/throwntom/terminal_input_test.go`

**Step 1: Write the failing tests**

Add parser-focused tests (pure function) for byte-to-key mapping:

```go
func TestParseKeyEventPrintable(t *testing.T) {
	ev, ok := parseKeyEvent([]byte{'a'})
	if !ok || ev.kind != keyPrintable || ev.r != 'a' {
		t.Fatalf("unexpected key event: %+v ok=%t", ev, ok)
	}
}

func TestParseKeyEventBackspace(t *testing.T) {
	for _, b := range []byte{0x08, 0x7f} {
		ev, ok := parseKeyEvent([]byte{b})
		if !ok || ev.kind != keyBackspace {
			t.Fatalf("unexpected key event for %x: %+v ok=%t", b, ev, ok)
		}
	}
}

func TestParseKeyEventEnter(t *testing.T) {
	for _, b := range []byte{'\r', '\n'} {
		ev, ok := parseKeyEvent([]byte{b})
		if !ok || ev.kind != keyEnter {
			t.Fatalf("unexpected key event for %x: %+v ok=%t", b, ev, ok)
		}
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s ./cmd/throwntom -run 'TestParseKeyEventPrintable|TestParseKeyEventBackspace|TestParseKeyEventEnter' -v`

Expected: FAIL because parser/helper does not exist.

**Step 3: Write minimal implementation**

Implement `parseKeyEvent` and raw-mode entry/restore helpers in unix build:

```go
func parseKeyEvent(buf []byte) (keyEvent, bool) {
	if len(buf) == 0 {
		return keyEvent{}, false
	}
	switch buf[0] {
	case '\r', '\n':
		return keyEvent{kind: keyEnter}, true
	case 0x08, 0x7f:
		return keyEvent{kind: keyBackspace}, true
	default:
		r := rune(buf[0])
		if r >= 32 && r != 127 {
			return keyEvent{kind: keyPrintable, r: r}, true
		}
		return keyEvent{}, false
	}
}
```

Add raw terminal state functions using `syscall` termios and restore guard.

**Step 4: Run test to verify it passes**

Run same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add cmd/throwntom/terminal_input_unix.go cmd/throwntom/terminal_input_test.go cmd/throwntom/interactive_model.go
git commit -m "feat: add terminal key parsing and raw mode helpers"
```

### Task 4: Build Shared Interactive Loop and Integrate Run/Shell Modes

**Files:**
- Create: `cmd/throwntom/interactive_loop.go`
- Create: `cmd/throwntom/interactive_loop_test.go`
- Modify: `cmd/throwntom/modes.go`
- Modify: `cmd/throwntom/main_test.go`

**Step 1: Write the failing tests**

Add loop-level tests with injected fake channels/callbacks:

```go
func TestInteractiveLoopTickRedrawKeepsPromptBuffer(t *testing.T) {
	// Arrange loop with fake key/tick channels and writer buffer
	// Type "st", trigger tick, assert output contains "command> st"
}

func TestInteractiveLoopResizeRedrawKeepsPromptVisible(t *testing.T) {
	// Type partial input, trigger resize event, assert prompt line remains present
}

func TestInteractiveLoopEnterExecutesCommandAndClearsInput(t *testing.T) {
	// Type "status" + enter, assert command callback sees "status" and prompt clears
}
```

Also update/remove obsolete `shouldRenderStatus` expectations in `main_test.go` once the scanner-specific gate is replaced.

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s ./cmd/throwntom -run 'TestInteractiveLoopTickRedrawKeepsPromptBuffer|TestInteractiveLoopResizeRedrawKeepsPromptVisible|TestInteractiveLoopEnterExecutesCommandAndClearsInput|TestShouldRenderStatus' -v`

Expected: FAIL because interactive loop plumbing does not exist yet.

**Step 3: Write minimal implementation**

Implement loop with explicit dependencies:

```go
type interactiveCallbacks struct {
	StatusSnapshot func() (string, bool)
	Execute        func(string) (daemonControlResponse, error)
}

func runInteractiveLoop(ui *terminalUI, in io.Reader, cb interactiveCallbacks) error {
	// enter raw mode
	// start ticker + sigwinch listener
	// read keys, apply reducer, redraw full frame
	// on enter -> execute callback, update message/status, redraw
	// exit when response.Exit is true
}
```

Integrate `runLocalMode` and `runShellMode` by constructing mode-specific callbacks and replacing `bufio.Scanner` loops.

**Step 4: Run test to verify it passes**

Run same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add cmd/throwntom/interactive_loop.go cmd/throwntom/interactive_loop_test.go cmd/throwntom/modes.go cmd/throwntom/main_test.go
git commit -m "feat: use raw interactive loop for run and shell modes"
```

### Task 5: Final Verification and Documentation Touch-Up

**Files:**
- Modify: `README.md` (if behavior wording is inaccurate)
- Modify: `cmd/throwntom/readme_test.go` (if README command text assertions need updates)

**Step 1: Write failing test/doc assertion (if required)**

If README behavior text changed, update/add assertion first:

```go
func TestReadmeMentionsInteractiveThreeLinePrompt(t *testing.T) {
	// assert README describes interactive shell behavior accurately
}
```

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s ./cmd/throwntom -run TestReadme -v`

Expected: FAIL only if doc assertions were intentionally changed.

**Step 3: Write minimal implementation**

Update README wording and corresponding readme tests only as needed.

**Step 4: Run full verification**

Run:
- `go test -timeout 30s ./...`

Expected: PASS with no new warnings.

**Step 5: Commit**

```bash
git add README.md cmd/throwntom/readme_test.go
git commit -m "docs: align interactive prompt behavior description"
```
