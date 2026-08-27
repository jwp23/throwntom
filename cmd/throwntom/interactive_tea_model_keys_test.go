package main

import (
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/engine"
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
				Response: core.Response{
					StatusLine:     testStatusIdle,
					MorningPending: false,
					Message:        "ok",
				},
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

func TestInteractiveTeaModelEnterInAwaitingConfirmSubmitsEmpty(t *testing.T) {
	var calls int
	var submitted string
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return "Confirm to continue  Today: 1  Cycle: 1/4", engine.AwaitingConfirm, false
		},
		Execute: func(command string) (commandResponse, error) {
			calls++
			submitted = command
			return commandResponse{
				Response: core.Response{
					StatusLine:     "Short break  04:59  Today: 1  Cycle: 1/4",
					EngineState:    engine.ShortBreak,
					MorningPending: false,
					Message:        "Confirmed -- short break",
				},
			}, nil
		},
	})

	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyEnter})

	if calls != 1 {
		t.Fatalf("expected Execute to be called once on bare enter in AwaitingConfirm, got %d", calls)
	}
	if submitted != "" {
		t.Fatalf("expected empty submitted command on bare enter, got %q", submitted)
	}
	view := next.(interactiveTeaModel).View()
	if !strings.Contains(view, "Short break") {
		t.Fatalf("expected view to reflect new state, got %q", view)
	}
}

func TestInteractiveTeaModelEnterIdleStillNoop(t *testing.T) {
	var calls int
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			calls++
			return commandResponse{}, nil
		},
	})

	_, _ = model.Update(tea.KeyMsg{Type: tea.KeyEnter})

	if calls != 0 {
		t.Fatalf("expected bare enter in Idle to be a no-op, got %d Execute calls", calls)
	}
}

func TestInteractiveTeaModelAwaitingConfirmShowsNextStageOnSecondLine(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return "Confirm to continue  Today: 1  Cycle: 1/4", engine.AwaitingConfirm, false
		},
		SecondaryStatus: func() string {
			return nextStageLabel(engine.ShortBreak, 5*time.Minute)
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{}, nil
		},
	})

	view := model.View()
	lines := strings.Split(view, "\n")

	statusIdx, nextIdx := -1, -1
	for i, line := range lines {
		if strings.Contains(line, "Confirm to continue") && strings.Contains(line, "Today: 1") && strings.Contains(line, "Cycle: 1/4") {
			statusIdx = i
		}
		if strings.Contains(line, "Next:") && strings.Contains(line, "short break") && strings.Contains(line, "press enter to start") {
			nextIdx = i
		}
	}

	if statusIdx < 0 {
		t.Fatalf("expected status line preserved (with label+stats) on its own line, got %q", view)
	}
	if nextIdx < 0 {
		t.Fatalf("expected next-stage line, got %q", view)
	}
	if nextIdx != statusIdx+1 {
		t.Fatalf("expected next-stage to be immediately below status line, got status at %d, next at %d: %q", statusIdx, nextIdx, view)
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
				Response: core.Response{
					StatusLine:     testStatusIdle,
					MorningPending: false,
					Message:        "ok",
				},
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

func TestInteractiveTeaModelQuestionMarkTogglesHelp(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		HelpLines: strings.Split(core.Help(), "\n"),
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
		HelpLines: strings.Split(core.Help(), "\n"),
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

func TestEnterInFocusPromptCallsExecuteWithEmptyString(t *testing.T) {
	var executedCommand *string
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(command string) (commandResponse, error) {
			executedCommand = &command
			return commandResponse{
				Response: core.Response{
					StatusLine: "pomodoro | 25:00",
					Message:    "Pomodoro started -- let's go!",
				},
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
				Response: core.Response{
					StatusLine: testStatusIdle,
					Message:    "task selection cancelled",
				},
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

func TestEscDismissesStatsView(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
		},
		Execute: func(string) (commandResponse, error) {
			return commandResponse{
				Response: core.Response{
					StatusLine: testStatusIdle,
				},
				StatsView: "-- Today --\nPomodoros: 5",
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
