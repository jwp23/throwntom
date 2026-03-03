package main

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func TestInteractiveTeaModelEnterExecutesAndClearsPrompt(t *testing.T) {
	var submitted string
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00", false
		},
		Execute: func(command string) (daemonControlResponse, error) {
			submitted = command
			return daemonControlResponse{
				StatusLine:     "idle | 00:00",
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
	if !hasLineWithPrefix(view, "message: ok") {
		t.Fatalf("expected view to include message line, got %q", view)
	}
	if !hasLineWithPrefix(view, "command> ") {
		t.Fatalf("expected prompt line in view, got %q", view)
	}
	if strings.Contains(view, "command> st") {
		t.Fatalf("expected prompt to clear after enter, got %q", view)
	}
}

func TestInteractiveTeaModelTickRefreshesStatusAndKeepsPrompt(t *testing.T) {
	statusLine := "idle | 00:00"
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, bool) {
			return statusLine, false
		},
		Execute: func(string) (daemonControlResponse, error) {
			return daemonControlResponse{}, nil
		},
	})

	next, _ := model.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'s'}})
	statusLine = "pomodoro | 24:59"
	next, _ = next.(interactiveTeaModel).Update(interactiveTickMsg{})

	view := next.(interactiveTeaModel).View()
	if !hasLineWithPrefix(view, "status: pomodoro | 24:59 morning reminder pending=false") {
		t.Fatalf("expected tick refresh to update status line, got %q", view)
	}
	if !hasLineWithPrefix(view, "command> s") {
		t.Fatalf("expected prompt to persist across tick redraw, got %q", view)
	}
}

func TestInteractiveTeaModelResizeClampsViewWidth(t *testing.T) {
	model := newInteractiveTeaModel(interactiveCallbacks{
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00 | today's pomodoros=0 | pomodoros=0/4", false
		},
		Execute: func(string) (daemonControlResponse, error) {
			return daemonControlResponse{}, nil
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
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00 | today's pomodoros=0 | pomodoros=0/4", false
		},
		Execute: func(string) (daemonControlResponse, error) {
			return daemonControlResponse{}, nil
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
			"daemon commands:",
		},
		StatusSnapshot: func() (string, bool) {
			return "idle | 00:00 | today's pomodoros=0 | pomodoros=0/4", false
		},
		Execute: func(string) (daemonControlResponse, error) {
			return daemonControlResponse{}, nil
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
	if !strings.HasPrefix(lines[1], "daemon commands:") {
		t.Fatalf("expected second header line, got %q", lines[1])
	}
	for idx, line := range lines {
		if len([]rune(line)) > 31 {
			t.Fatalf("expected line %d to clamp under width to avoid wrap, got %d chars in %q", idx, len([]rune(line)), line)
		}
	}
}

func hasLineWithPrefix(view string, prefix string) bool {
	for _, line := range strings.Split(view, "\n") {
		if strings.HasPrefix(line, prefix) {
			return true
		}
	}
	return false
}
