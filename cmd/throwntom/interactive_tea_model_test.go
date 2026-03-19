package main

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

const (
	testStatusIdle     = "Idle  Today: 0  Cycle: 0/4"
	testStatusIdleFull = "Idle  Today: 0  Cycle: 0/4"
	testCommandsHeader = "commands:"
	testHelpHint       = "?: help"
	testFocusHeader    = "Focus:"
)

func TestInteractiveTeaModelEnterExecutesAndClearsPrompt(t *testing.T) {
	var submitted string
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(command string) (commandResponse, error) {
			submitted = command
			return commandResponse{
				StatusLine:     testStatusIdle,
				MorningPending: false,
				Message:        "ok",
			}, nil
		},
	})

	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'s'}})
	next, _ = next.(interactiveTeaModel).Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'t'}})
	next, _ = next.(interactiveTeaModel).Update(tea.KeyMsg{Type: tea.KeyEnter})

	if submitted != "st" {
		t.Fatalf("expected submitted command %q, got %q", "st", submitted)
	}

	view := next.(interactiveTeaModel).View()
	if !strings.Contains(view, "ok") {
		t.Fatalf("expected view to include message, got %q", view)
	}
	if !strings.Contains(view, "> ") {
		t.Fatalf("expected prompt line in view, got %q", view)
	}
	if strings.Contains(view, "> st") {
		t.Fatalf("expected prompt to clear after enter, got %q", view)
	}
}

func TestInteractiveTeaModelSpaceKeyIncludedInSubmittedCommand(t *testing.T) {
	var submitted string
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(command string) (commandResponse, error) {
			submitted = command
			return commandResponse{
				StatusLine:     testStatusIdle,
				MorningPending: false,
				Message:        "ok",
			}, nil
		},
	})

	input := []tea.KeyMsg{
		{Type: tea.KeyRunes, Runes: []rune("snooze")},
		{Type: tea.KeySpace},
		{Type: tea.KeyRunes, Runes: []rune("10m")},
		{Type: tea.KeyEnter},
	}

	next := tea.Model(model)
	for _, key := range input {
		next, _ = next.Update(key)
	}

	if submitted != "snooze 10m" {
		t.Fatalf("expected submitted command %q, got %q", "snooze 10m", submitted)
	}
}

func TestInteractiveTeaModelTickRefreshesStatusAndKeepsPrompt(t *testing.T) {
	statusLine := testStatusIdle
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return statusLine, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{}, nil
		},
	})

	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'s'}})
	statusLine = "Pomodoro  24:59  Today: 0  Cycle: 0/4"
	next, _ = next.(interactiveTeaModel).Update(interactiveTickMsg{})

	view := next.(interactiveTeaModel).View()
	if !strings.Contains(view, "Pomodoro") || !strings.Contains(view, "24:59") {
		t.Fatalf("expected tick refresh to update status line, got %q", view)
	}
	if !strings.Contains(view, "> s") {
		t.Fatalf("expected prompt to persist across tick redraw, got %q", view)
	}
}

func TestInteractiveTeaModelResizeClampsViewWidth(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdleFull, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{}, nil
		},
	})

	next, _ := model.Update(tea.WindowSizeMsg{Width: 24, Height: 10})
	view := next.(interactiveTeaModel).View()

	lines := strings.Split(view, "\n")
	if len(lines) != 3 {
		t.Fatalf("expected 3 lines in view, got %d from %q", len(lines), view)
	}
	for idx, line := range lines {
		if len([]rune(line)) > 24 {
			t.Fatalf("expected line %d to clamp to width 24, got %d chars in %q", idx, len([]rune(line)), line)
		}
	}
}

func TestInteractiveTeaModelResizeZeroWidthKeepsPreviousClamp(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdleFull, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{}, nil
		},
	})

	next, _ := model.Update(tea.WindowSizeMsg{Width: 24, Height: 10})
	next, _ = next.(interactiveTeaModel).Update(tea.WindowSizeMsg{Width: 0, Height: 10})
	view := next.(interactiveTeaModel).View()

	for idx, line := range strings.Split(view, "\n") {
		if len([]rune(line)) > 23 {
			t.Fatalf("expected line %d to retain prior width clamp after zero-width resize, got %d chars in %q", idx, len([]rune(line)), line)
		}
	}
}

func TestInteractiveTeaModelViewIncludesPersistentHeaderLines(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		HeaderLines: []string{
			"throwntom run mode started (schedule Mon,Tue,Wed,Thu,Fri 09:00)",
			testCommandsHeader,
		},
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdleFull, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{}, nil
		},
	})

	next, _ := model.Update(tea.WindowSizeMsg{Width: 32, Height: 10})
	view := next.(interactiveTeaModel).View()
	lines := strings.Split(view, "\n")
	if len(lines) != 5 {
		t.Fatalf("expected header + 3 frame lines, got %d lines in %q", len(lines), view)
	}
	if !strings.HasPrefix(lines[0], "throwntom run mode started") {
		t.Fatalf("expected first header line, got %q", lines[0])
	}
	if !strings.HasPrefix(lines[1], testCommandsHeader) {
		t.Fatalf("expected second header line, got %q", lines[1])
	}
	for idx, line := range lines {
		if len([]rune(line)) > 31 {
			t.Fatalf("expected line %d to clamp under width to avoid wrap, got %d chars in %q", idx, len([]rune(line)), line)
		}
	}
}

func TestInteractiveTeaModelHelpHiddenByDefault(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		HeaderLines: []string{"throwntom run mode started"},
		HelpLines:   strings.Split(commandsHelp(), "\n"),
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{}, nil
		},
	})

	view := model.View()
	if !strings.Contains(view, testHelpHint) {
		t.Fatalf("expected hint line '?: help' when help is hidden, got %q", view)
	}
	if strings.Contains(view, testCommandsHeader) {
		t.Fatalf("expected help to be hidden by default, but found 'commands:' in %q", view)
	}
}

func TestInteractiveTeaModelQuestionMarkTogglesHelp(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		HelpLines: strings.Split(commandsHelp(), "\n"),
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{}, nil
		},
	})

	// Initially hidden
	view := model.View()
	if strings.Contains(view, testCommandsHeader) {
		t.Fatalf("expected help hidden initially, got %q", view)
	}

	// Press ? to show
	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})
	view = next.(interactiveTeaModel).View()
	if !strings.Contains(view, testCommandsHeader) {
		t.Fatalf("expected help visible after ?, got %q", view)
	}
	if strings.Contains(view, testHelpHint) {
		t.Fatalf("expected hint hidden when help is shown, got %q", view)
	}

	// Press ? again to hide
	next, _ = next.(interactiveTeaModel).Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})
	view = next.(interactiveTeaModel).View()
	if strings.Contains(view, testCommandsHeader) {
		t.Fatalf("expected help hidden after second ?, got %q", view)
	}
	if !strings.Contains(view, testHelpHint) {
		t.Fatalf("expected hint visible after hiding help, got %q", view)
	}
}

func TestInteractiveTeaModelQuestionMarkTypedWhenInputNonEmpty(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		HelpLines: strings.Split(commandsHelp(), "\n"),
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{}, nil
		},
	})

	// Type 'a' then '?'
	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'a'}})
	next, _ = next.(interactiveTeaModel).Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'?'}})

	view := next.(interactiveTeaModel).View()
	if !strings.Contains(view, "> a?") {
		t.Fatalf("expected '?' typed as normal input when buffer non-empty, got %q", view)
	}
	if strings.Contains(view, testCommandsHeader) {
		t.Fatalf("expected help to stay hidden when '?' typed with non-empty input, got %q", view)
	}
}

// --- Task 12: Focus display in Bubble Tea UI tests ---

func TestViewShowsFocusLinesAboveStatus(t *testing.T) {
	m := interactiveTeaModel{
		statusLine:  "Pomodoro  24:30  Today: 1  Cycle: 1/4",
		engineState: engine.Work,
		focusLines:  []string{testFocusHeader, "  1. important task"},
		width:       120,
	}
	view := m.View()
	focusIdx := strings.Index(view, testFocusHeader)
	statusIdx := strings.Index(view, "Pomodoro")
	if focusIdx == -1 {
		t.Fatal("expected Focus: in view")
	}
	if statusIdx == -1 {
		t.Fatal("expected status content in view")
	}
	if focusIdx >= statusIdx {
		t.Fatal("expected focus lines above status line")
	}
}

func TestViewShowsFocusPromptWhenPending(t *testing.T) {
	m := interactiveTeaModel{
		focusPrompt: "Select tasks for this pomodoro:\n 1) do thing\n\n(numbers to toggle, a <desc> to add, enter to start)",
		width:       120,
	}
	view := m.View()
	if !strings.Contains(view, "Select tasks") {
		t.Fatal("expected focus prompt in view")
	}
	if !strings.Contains(view, ">") {
		t.Fatal("expected prompt in focus prompt view")
	}
}

func TestViewHidesFocusLinesWhenEmpty(t *testing.T) {
	m := interactiveTeaModel{
		statusLine: testStatusIdle,
		width:      120,
	}
	view := m.View()
	if strings.Contains(view, testFocusHeader) {
		t.Fatal("expected no focus lines")
	}
}

func TestEnterInFocusPromptCallsExecuteWithEmptyString(t *testing.T) {
	var executedCommand *string
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(command string) (commandResponse, error) {
			executedCommand = &command
			return commandResponse{
				StatusLine: "pomodoro | 25:00",
				Message:    "Pomodoro started -- let's go!",
			}, nil
		},
	})

	// Simulate being in focus prompt mode
	model.focusPrompt = "Select tasks for this pomodoro:\n\n(numbers to toggle, a <desc> to add, enter to start, esc to cancel)"

	// Press Enter with empty input
	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyEnter})

	if executedCommand == nil {
		t.Fatal("expected Execute to be called with empty string, but it was not called")
	}
	if *executedCommand != "" {
		t.Fatalf("expected empty string command, got %q", *executedCommand)
	}
	m := next.(interactiveTeaModel)
	if m.message != "Pomodoro started -- let's go!" {
		t.Fatalf("expected message 'pomodoro started', got %q", m.message)
	}
}

func TestEscCancelsFocusPrompt(t *testing.T) {
	var cancelCalled bool
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{}, nil
		},
		CancelFocus: func() commandResponse {
			cancelCalled = true
			return commandResponse{
				StatusLine: testStatusIdle,
				Message:    "task selection cancelled",
			}
		},
	})

	// Simulate being in focus prompt mode
	model.focusPrompt = "Select tasks for this pomodoro:\n 1) do thing\n\n(numbers to toggle, a <desc> to add, enter to start, esc to cancel)"
	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyEsc})

	if !cancelCalled {
		t.Fatal("expected CancelFocus callback to be called")
	}
	m := next.(interactiveTeaModel)
	if m.focusPrompt != "" {
		t.Fatalf("expected focus prompt cleared, got %q", m.focusPrompt)
	}
}

func TestStatsViewRenderedFullScreen(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{
				StatusLine: testStatusIdle,
				StatsView:  "-- Today --\nPomodoros: 5",
			}, nil
		},
	})

	// Submit "stats" command
	next := tea.Model(model)
	for _, r := range "stats" {
		next, _ = next.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{r}})
	}
	next, _ = next.Update(tea.KeyMsg{Type: tea.KeyEnter})

	view := next.(interactiveTeaModel).View()
	if !strings.Contains(view, "-- Today --") {
		t.Fatalf("expected stats view content, got %q", view)
	}
	if !strings.Contains(view, "esc: back") {
		t.Fatalf("expected 'esc: back' hint, got %q", view)
	}
	// Should NOT contain normal frame elements
	if strings.Contains(view, "> ") {
		t.Fatalf("expected no prompt in stats view, got %q", view)
	}
}

func TestEscDismissesStatsView(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{
				StatusLine: testStatusIdle,
				StatsView:  "-- Today --\nPomodoros: 5",
			}, nil
		},
	})

	// Submit "stats" to enter stats view
	next := tea.Model(model)
	for _, r := range "stats" {
		next, _ = next.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{r}})
	}
	next, _ = next.Update(tea.KeyMsg{Type: tea.KeyEnter})

	// Verify stats view is showing
	m := next.(interactiveTeaModel)
	if m.statsView == "" {
		t.Fatal("expected statsView to be set")
	}

	// Press Escape
	next, _ = m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	m = next.(interactiveTeaModel)
	if m.statsView != "" {
		t.Fatalf("expected statsView cleared after Esc, got %q", m.statsView)
	}

	// View should show normal frame
	view := m.View()
	if strings.Contains(view, "-- Today --") {
		t.Fatal("expected stats view dismissed after Esc")
	}
	if !strings.Contains(view, "> ") {
		t.Fatalf("expected prompt to appear after dismissing stats view, got %q", view)
	}
}

func TestEscDoesNothingWhenNoFocusPrompt(t *testing.T) {
	var cancelCalled bool
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{}, nil
		},
		CancelFocus: func() commandResponse {
			cancelCalled = true
			return commandResponse{}
		},
	})

	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyEsc})
	if cancelCalled {
		t.Fatal("CancelFocus should not be called when no focus prompt is active")
	}
	_ = next
}
