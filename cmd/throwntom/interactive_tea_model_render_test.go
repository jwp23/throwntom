package main

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/jwp23/throwntom/v3/internal/core"
	"github.com/jwp23/throwntom/v3/internal/engine"
)

const (
	testStatusIdle     = "Idle  Today: 0  Cycle: 0/4"
	testCommandsHeader = "commands:"
	testHelpHint       = "?: help"
	testFocusHeader    = "Focus:"
)

func TestInteractiveTeaModelResizeClampsViewWidth(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, engine.State, bool) {
			return testStatusIdle, engine.Idle, false
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
			return testStatusIdle, engine.Idle, false
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
			return testStatusIdle, engine.Idle, false
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
		HelpLines:   strings.Split(core.Help(), "\n"),
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

func TestStatsViewRenderedFullScreen(t *testing.T) {
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
