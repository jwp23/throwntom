# Interactive Status UI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `urgtomat` an interactive-terminal-only daemon with a continuously updating 1-second status line that coexists with basic command input editing.

**Architecture:** Split terminal rendering/input concerns from daemon command/state logic using a thin `terminalUI` boundary. Remove non-interactive and subcommand branches so there is one supported runtime path. Implement via Red/Green TDD with small, isolated commits.

**Tech Stack:** Go standard library (`bufio`, `os`, `time`, terminal file mode checks), existing internal packages, Go testing (`go test`).

---

### Task 1: Remove CLI subcommand requirement

**Files:**
- Modify: `cmd/urgtomat/main.go`
- Modify: `e2e/daemon_e2e_test.go`

**Step 1: Write the failing test**

Update e2e assertions to reflect direct startup:
- `TestDaemonStartsAndQuits`: run binary as `exec.Command(bin)` (no `daemon` arg).
- `TestMissingConfigFileFails`: run binary as `exec.Command(bin, "--config", missingPath)`.
- Add new e2e test `TestUnexpectedPositionalArgExitsNonZero` for `exec.Command(bin, "daemon")` expecting usage/arg error.

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s -tags e2e ./e2e -run 'TestDaemonStartsAndQuits|TestMissingConfigFileFails|TestUnexpectedPositionalArgExitsNonZero' -v`
Expected: FAIL because current CLI still expects `daemon`.

**Step 3: Write minimal implementation**

In `main.go`:
- Remove command switch.
- If `flag.NArg() != 0`, print usage + positional-arg error and exit non-zero.
- Call `runDaemon(cfg)` directly when args are valid.
- Update `printUsage()` text to `usage: urgtomat [--config path]`.

**Step 4: Run test to verify it passes**

Run same e2e command from Step 2.
Expected: PASS.

**Step 5: Commit**

```bash
git add cmd/urgtomat/main.go e2e/daemon_e2e_test.go
git commit -m "refactor: run daemon directly without subcommand"
```

### Task 2: Enforce interactive-terminal-only runtime

**Files:**
- Modify: `cmd/urgtomat/main.go`
- Modify: `cmd/urgtomat/main_test.go`
- Modify: `README.md`

**Step 1: Write the failing test**

In `main_test.go`:
- Replace/remove `TestShouldStartLiveStatusRenderer`.
- Add tests for new helper, e.g. `requiresInteractiveTTY(stdinTTY, stdoutTTY bool) error`:
  - returns `nil` when both true
  - returns error when either false

Add/adjust daemon startup behavior test coverage by asserting returned/printed error path helper behavior, not process-level exit.

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s ./cmd/urgtomat -run 'TestRequiresInteractiveTTY|TestShouldStartLiveStatusRenderer' -v`
Expected: FAIL because helper does not exist and legacy test expects old behavior.

**Step 3: Write minimal implementation**

In `main.go`:
- Remove `shouldStartLiveStatusRenderer` and branch logic.
- Add precondition before starting UI loop:
  - both `isTerminal(os.Stdin)` and `isTerminal(os.Stdout)` must be true
  - otherwise print `daemon requires an interactive terminal` and return non-zero exit path (or exit in `runDaemon` via current style)

In `README.md`:
- Remove mention/implied support of non-interactive mode.
- Update run examples to `./urgtomat` and `./urgtomat --config ./urgtomat.toml`.

**Step 4: Run test to verify it passes**

Run: `go test -timeout 30s ./cmd/urgtomat -run 'TestRequiresInteractiveTTY|TestShouldStartLiveStatusRenderer' -v`
Expected: PASS with updated test names/assertions.

**Step 5: Commit**

```bash
git add cmd/urgtomat/main.go cmd/urgtomat/main_test.go README.md
git commit -m "feat: require interactive terminal for daemon runtime"
```

### Task 3: Introduce terminal UI model and renderer (no raw input yet)

**Files:**
- Create: `cmd/urgtomat/terminal_ui.go`
- Create: `cmd/urgtomat/terminal_ui_test.go`
- Modify: `cmd/urgtomat/main.go`

**Step 1: Write the failing test**

In `terminal_ui_test.go` add unit tests for a pure renderer function (e.g. `renderFrame(statusLine string, morningPending bool, input string) string`):
- includes `status: <statusLine> morning_pending=<bool>`
- includes `command> <input>`
- output overwrites previous content safely (assert expected control sequence/format chosen by implementation)

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s ./cmd/urgtomat -run 'TestRenderFrame' -v`
Expected: FAIL because file/functions do not exist.

**Step 3: Write minimal implementation**

Implement `terminal_ui.go` with:
- small state struct for input buffer
- pure render helper used by tests
- print function used by main loop to redraw frame

Wire main loop to call renderer for status + prompt instead of mixed `fmt.Print("\ncommand> ")` style.

**Step 4: Run test to verify it passes**

Run: `go test -timeout 30s ./cmd/urgtomat -run 'TestRenderFrame' -v`
Expected: PASS.

**Step 5: Commit**

```bash
git add cmd/urgtomat/terminal_ui.go cmd/urgtomat/terminal_ui_test.go cmd/urgtomat/main.go
git commit -m "feat: add terminal ui renderer for status and prompt"
```

### Task 4: Add basic interactive line editing with stable 1-second redraw

**Files:**
- Modify: `cmd/urgtomat/terminal_ui.go`
- Modify: `cmd/urgtomat/terminal_ui_test.go`
- Modify: `cmd/urgtomat/main.go`

**Step 1: Write the failing test**

In `terminal_ui_test.go` add state transition tests for input handling function (pure where possible), e.g.:
- printable char appends
- backspace removes one rune when buffer non-empty
- enter emits command and clears buffer

In `main_test.go` or dedicated loop test file, add test for render-trigger policy:
- 1-second ticker triggers redraw
- edit/submit events trigger immediate redraw.

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s ./cmd/urgtomat -run 'TestInputEdit|TestEnterSubmits|TestRedrawTriggers' -v`
Expected: FAIL until input event loop is implemented.

**Step 3: Write minimal implementation**

Implement in `terminal_ui.go`:
- event loop reading bytes/runes from stdin
- basic key handling: printable/backspace/enter
- channel or callback to deliver submitted commands to existing command handler
- ticker-driven redraw at exactly 1s cadence
- immediate redraw on edit and command completion notifications

Integrate in `main.go`:
- replace scanner loop with UI-driven command submit callback.
- keep existing command semantics (`start`, `confirm`, `snooze`, etc.) unchanged.

**Step 4: Run test to verify it passes**

Run: `go test -timeout 30s ./cmd/urgtomat -run 'TestInputEdit|TestEnterSubmits|TestRedrawTriggers' -v`
Expected: PASS.

**Step 5: Commit**

```bash
git add cmd/urgtomat/terminal_ui.go cmd/urgtomat/terminal_ui_test.go cmd/urgtomat/main.go
git commit -m "feat: support basic interactive input with 1s status redraw"
```

### Task 5: Adapt e2e coverage for new CLI/runtime constraints

**Files:**
- Modify: `e2e/daemon_e2e_test.go`

**Step 1: Write the failing test**

Add/adjust tests:
- keep direct-start quit path test (from Task 1)
- add non-interactive rejection test by launching process with piped stdio and expecting `daemon requires an interactive terminal`.

**Step 2: Run test to verify it fails**

Run: `go test -timeout 30s -tags e2e ./e2e -run 'TestDaemonStartsAndQuits|TestNonInteractiveRejected' -v`
Expected: FAIL before full behavior is wired.

**Step 3: Write minimal implementation**

If needed, refine startup precondition/error path in `main.go` so new e2e behavior is deterministic and exits non-zero.

**Step 4: Run test to verify it passes**

Run same e2e command from Step 2.
Expected: PASS.

**Step 5: Commit**

```bash
git add e2e/daemon_e2e_test.go cmd/urgtomat/main.go
git commit -m "test: cover direct startup and non-interactive rejection"
```

### Task 6: Full verification and cleanup

**Files:**
- Modify: `cmd/urgtomat/main.go` (only if needed)
- Modify: `cmd/urgtomat/main_test.go` (only if needed)
- Modify: `README.md` (if usage/help text drift remains)

**Step 1: Run full suite with required timeout**

Run: `go test -timeout 30s ./...`
Expected: PASS.

**Step 2: Build check**

Run: `go build ./cmd/urgtomat`
Expected: success, no new warnings.

**Step 3: Final review pass**

Verify:
- no references to mandatory `daemon` positional command remain in docs/tests/code
- no non-interactive live-render branch remains
- status redraw cadence remains 1 second
- input scope remains basic only

**Step 4: Commit final touch-ups (if any)**

```bash
git add cmd/urgtomat/main.go cmd/urgtomat/main_test.go README.md
git commit -m "chore: finalize interactive status ui migration"
```
