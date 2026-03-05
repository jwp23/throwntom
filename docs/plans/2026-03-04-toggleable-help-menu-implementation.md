# Toggleable Help Menu Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Hide the daemon commands help text by default, show a `?: help` hint, and let users toggle the full help with `?`.

**Architecture:** Add a `showHelp` bool and `helpLines` slice to the Bubble Tea model. Split help lines out of `HeaderLines` into a new `HelpLines` field on `interactiveCallbacks`. The `?` key toggles visibility when the input buffer is empty.

**Tech Stack:** Go, Bubble Tea

---

### Task 1: Add HelpLines field to interactiveCallbacks

**Files:**
- Modify: `cmd/throwntom/interactive_callbacks.go:3-7`

**Step 1: Write the failing test**

Add to `cmd/throwntom/modes_bubbletea_test.go`:

```go
func TestLocalModeCallbacksHelpLinesContainCommandsHelp(t *testing.T) {
	cfg := config.Default()
	core := newDaemonCore(cfg, notifier.NewTestNotifier(func(string, ...string) error {
		return fmt.Errorf("unused")
	}))

	callbacks := localModeCallbacks(cfg, core)
	if len(callbacks.HelpLines) == 0 {
		t.Fatal("expected local mode callbacks to include help lines")
	}
	foundCommandsHeader := false
	for _, line := range callbacks.HelpLines {
		if line == "daemon commands:" {
			foundCommandsHeader = true
		}
	}
	if !foundCommandsHeader {
		t.Fatal("expected help lines to contain 'daemon commands:' header")
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test ./cmd/throwntom/ -run TestLocalModeCallbacksHelpLinesContainCommandsHelp -v`
Expected: FAIL — `HelpLines` field does not exist.

**Step 3: Add HelpLines field**

In `cmd/throwntom/interactive_callbacks.go`, add `HelpLines` to the struct:

```go
type interactiveCallbacks struct {
	HeaderLines    []string
	HelpLines      []string
	StatusSnapshot func() (string, bool)
	Execute        func(command string) (daemonControlResponse, error)
}
```

**Step 4: Run test to verify it fails for the right reason**

Run: `go test ./cmd/throwntom/ -run TestLocalModeCallbacksHelpLinesContainCommandsHelp -v`
Expected: FAIL — `HelpLines` is empty (not populated yet).

**Step 5: Move help lines from HeaderLines to HelpLines in localModeCallbacks**

In `cmd/throwntom/modes.go`, change `localModeCallbacks` (lines 95-109):

```go
func localModeCallbacks(cfg config.Config, core *daemonCore) interactiveCallbacks {
	header := []string{
		fmt.Sprintf("throwntom run mode started (schedule %s %s)", strings.Join(cfg.Schedule.Days, ","), cfg.Schedule.Time),
		fmt.Sprintf("cycle: work=%dm short=%dm long=%dm every=%d repeat=%ds", cfg.WorkMinutes, cfg.ShortBreakMinutes, cfg.LongBreakMinutes, cfg.LongBreakEvery, cfg.RepeatSecs),
	}

	return interactiveCallbacks{
		HeaderLines:    header,
		HelpLines:      strings.Split(daemonCommandsHelp(), "\n"),
		StatusSnapshot: core.snapshot,
		Execute: func(command string) (daemonControlResponse, error) {
			return core.executeControlCommand(command), nil
		},
	}
}
```

**Step 6: Move help lines from HeaderLines to HelpLines in shellModeCallbacks**

In `cmd/throwntom/modes.go`, change `shellModeCallbacks` (lines 111-135). Replace the `HeaderLines` construction:

```go
	return interactiveCallbacks{
		HeaderLines: []string{fmt.Sprintf("throwntom shell connected to daemon at %s", socketPath)},
		HelpLines:   strings.Split(daemonCommandsHelp(), "\n"),
		StatusSnapshot: statusSnapshot,
		Execute: func(command string) (daemonControlResponse, error) {
			resp, execErr := sendControlCommand(socketPath, command)
			if execErr != nil {
				return daemonControlResponse{}, fmt.Errorf("control error: %w", execErr)
			}
			cache.Set(resp.StatusLine, resp.MorningPending)
			return resp, nil
		},
	}
```

**Step 7: Run test to verify it passes**

Run: `go test ./cmd/throwntom/ -run TestLocalModeCallbacksHelpLinesContainCommandsHelp -v`
Expected: PASS

**Step 8: Run all tests to check for regressions**

Run: `go test ./cmd/throwntom/ -v`
Expected: All pass. The existing `TestLocalModeCallbacksExecuteDelegatesToCore` still passes because `HeaderLines` still has the mode/config lines.

**Step 9: Commit**

```bash
git add cmd/throwntom/interactive_callbacks.go cmd/throwntom/modes.go cmd/throwntom/modes_bubbletea_test.go
git commit -m "refactor: split help lines into separate HelpLines callback field"
```

---

### Task 2: Add showHelp toggle and helpLines to the model

**Files:**
- Modify: `cmd/throwntom/interactive_tea_model.go:12-30`
- Modify: `cmd/throwntom/interactive_tea_model_test.go`

**Step 1: Write the failing test for help hidden by default**

Add to `cmd/throwntom/interactive_tea_model_test.go`:

```go
func TestInteractiveTeaModelHelpHiddenByDefault(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		HeaderLines: []string{"throwntom run mode started"},
		HelpLines:   strings.Split(daemonCommandsHelp(), "\n"),
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00", false
		},
		Execute: func(string) (daemonControlResponse, error) {
			return daemonControlResponse{}, nil
		},
	})

	view := model.View()
	if !strings.Contains(view, "?: help") {
		t.Fatalf("expected hint line '?: help' when help is hidden, got %q", view)
	}
	if strings.Contains(view, "daemon commands:") {
		t.Fatalf("expected help to be hidden by default, but found 'daemon commands:' in %q", view)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test ./cmd/throwntom/ -run TestInteractiveTeaModelHelpHiddenByDefault -v`
Expected: FAIL — no `?: help` line in view.

**Step 3: Add helpLines and showHelp fields to model**

In `cmd/throwntom/interactive_tea_model.go`, update the struct and constructor:

```go
type interactiveTeaModel struct {
	callbacks      interactiveCallbacks
	headerLines    []string
	helpLines      []string
	showHelp       bool
	statusLine     string
	morningPending bool
	message        string
	prompt         promptState
	width          int
}

func newInteractiveTeaModel(callbacks interactiveCallbacks) interactiveTeaModel {
	statusLine, morningPending := callbacks.StatusSnapshot()
	return interactiveTeaModel{
		callbacks:      callbacks,
		headerLines:    append([]string(nil), callbacks.HeaderLines...),
		helpLines:      append([]string(nil), callbacks.HelpLines...),
		statusLine:     statusLine,
		morningPending: morningPending,
	}
}
```

**Step 4: Update View to show hint or full help**

In `cmd/throwntom/interactive_tea_model.go`, replace the `View()` method:

```go
func (m interactiveTeaModel) View() string {
	frame := renderFrameWithWidth(m.statusLine, m.morningPending, m.message, m.prompt.input, m.width)

	var header []string
	for _, line := range m.headerLines {
		header = append(header, clampTerminalLine(line, m.width))
	}
	if m.showHelp {
		for _, line := range m.helpLines {
			header = append(header, clampTerminalLine(line, m.width))
		}
	} else if len(m.helpLines) > 0 {
		header = append(header, clampTerminalLine("?: help", m.width))
	}

	if len(header) == 0 {
		return frame
	}
	return strings.Join(append(header, frame), "\n")
}
```

**Step 5: Run test to verify it passes**

Run: `go test ./cmd/throwntom/ -run TestInteractiveTeaModelHelpHiddenByDefault -v`
Expected: PASS

**Step 6: Update existing header test**

The existing `TestInteractiveTeaModelViewIncludesPersistentHeaderLines` puts `"daemon commands:"` in `HeaderLines`, which still works. But the line count changed because there's now a `"?: help"` hint when `HelpLines` is empty. Since this test doesn't set `HelpLines`, no hint appears, so it should still pass as-is. Verify:

Run: `go test ./cmd/throwntom/ -run TestInteractiveTeaModelViewIncludesPersistentHeaderLines -v`
Expected: PASS (no `HelpLines` set = no hint line added)

**Step 7: Run all tests**

Run: `go test ./cmd/throwntom/ -v`
Expected: All pass.

**Step 8: Commit**

```bash
git add cmd/throwntom/interactive_tea_model.go cmd/throwntom/interactive_tea_model_test.go
git commit -m "feat: hide help by default, show '?: help' hint"
```

---

### Task 3: Add ? key toggle

**Files:**
- Modify: `cmd/throwntom/interactive_tea_model.go:73-122` (updateKey)
- Modify: `cmd/throwntom/interactive_tea_model_test.go`

**Step 1: Write the failing test for ? toggle with empty input**

Add to `cmd/throwntom/interactive_tea_model_test.go`:

```go
func TestInteractiveTeaModelQuestionMarkTogglesHelp(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		HelpLines: strings.Split(daemonCommandsHelp(), "\n"),
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00", false
		},
		Execute: func(string) (daemonControlResponse, error) {
			return daemonControlResponse{}, nil
		},
	})

	// Initially hidden
	view := model.View()
	if strings.Contains(view, "daemon commands:") {
		t.Fatalf("expected help hidden initially, got %q", view)
	}

	// Press ? to show
	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})
	view = next.(interactiveTeaModel).View()
	if !strings.Contains(view, "daemon commands:") {
		t.Fatalf("expected help visible after ?, got %q", view)
	}
	if strings.Contains(view, "?: help") {
		t.Fatalf("expected hint hidden when help is shown, got %q", view)
	}

	// Press ? again to hide
	next, _ = next.(interactiveTeaModel).Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})
	view = next.(interactiveTeaModel).View()
	if strings.Contains(view, "daemon commands:") {
		t.Fatalf("expected help hidden after second ?, got %q", view)
	}
	if !strings.Contains(view, "?: help") {
		t.Fatalf("expected hint visible after hiding help, got %q", view)
	}
}
```

**Step 2: Run test to verify it fails**

Run: `go test ./cmd/throwntom/ -run TestInteractiveTeaModelQuestionMarkTogglesHelp -v`
Expected: FAIL — `?` is treated as a printable character, types into input, no toggle.

**Step 3: Write the failing test for ? as normal input when buffer is non-empty**

Add to `cmd/throwntom/interactive_tea_model_test.go`:

```go
func TestInteractiveTeaModelQuestionMarkTypedWhenInputNonEmpty(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		HelpLines: strings.Split(daemonCommandsHelp(), "\n"),
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00", false
		},
		Execute: func(string) (daemonControlResponse, error) {
			return daemonControlResponse{}, nil
		},
	})

	// Type 'a' then '?'
	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'a'}})
	next, _ = next.(interactiveTeaModel).Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})

	view := next.(interactiveTeaModel).View()
	if !strings.Contains(view, "command> a?") {
		t.Fatalf("expected '?' typed as normal input when buffer non-empty, got %q", view)
	}
	if strings.Contains(view, "daemon commands:") {
		t.Fatalf("expected help to stay hidden when '?' typed with non-empty input, got %q", view)
	}
}
```

**Step 4: Implement ? key toggle in updateKey**

In `cmd/throwntom/interactive_tea_model.go`, modify the `updateKey` method. Replace the `tea.KeyRunes` / `tea.KeySpace` block (lines 77-88):

```go
	if key.Type == tea.KeyRunes || key.Type == tea.KeySpace {
		runes := key.Runes
		if key.Type == tea.KeySpace {
			runes = []rune{' '}
		}
		if len(runes) == 1 && runes[0] == '?' && m.prompt.input == "" {
			m.showHelp = !m.showHelp
			return m, nil
		}
		for _, r := range runes {
			m.prompt, _, _ = applyKey(m.prompt, keyEvent{
				kind: keyPrintable,
				r:    r,
			})
		}
		return m, nil
	}
```

**Step 5: Run both tests to verify they pass**

Run: `go test ./cmd/throwntom/ -run "TestInteractiveTeaModelQuestionMark" -v`
Expected: Both PASS.

**Step 6: Run all tests**

Run: `go test ./cmd/throwntom/ -v`
Expected: All pass.

**Step 7: Commit**

```bash
git add cmd/throwntom/interactive_tea_model.go cmd/throwntom/interactive_tea_model_test.go
git commit -m "feat: toggle help with ? key when input is empty"
```

---

### Task 4: Final verification

**Step 1: Run full test suite**

Run: `go test ./...`
Expected: All pass.

**Step 2: Build and smoke test**

Run: `go build ./cmd/throwntom/`
Expected: Builds successfully.
