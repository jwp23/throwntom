package main

import (
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

type interactiveTickMsg struct{}

type interactiveTeaModel struct {
	callbacks      interactiveCallbacks
	headerLines    []string
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
		statusLine:     statusLine,
		morningPending: morningPending,
	}
}

func (m interactiveTeaModel) Init() tea.Cmd {
	return interactiveTickCmd()
}

func interactiveTickCmd() tea.Cmd {
	return tea.Tick(time.Second, func(time.Time) tea.Msg {
		return interactiveTickMsg{}
	})
}

func (m interactiveTeaModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.updateKey(msg)
	case interactiveTickMsg:
		m.statusLine, m.morningPending = m.callbacks.StatusSnapshot()
		return m, interactiveTickCmd()
	case tea.WindowSizeMsg:
		if msg.Width > 0 {
			m.width = msg.Width
		}
		return m, tea.ClearScreen
	default:
		return m, nil
	}
}

func (m interactiveTeaModel) View() string {
	frame := renderFrameWithWidth(m.statusLine, m.morningPending, m.message, m.prompt.input, m.width)
	if len(m.headerLines) == 0 {
		return frame
	}

	lines := make([]string, 0, len(m.headerLines)+1)
	for _, line := range m.headerLines {
		lines = append(lines, clampTerminalLine(line, m.width))
	}
	lines = append(lines, frame)
	return strings.Join(lines, "\n")
}

func (m interactiveTeaModel) updateKey(key tea.KeyMsg) (tea.Model, tea.Cmd) {
	if key.Type == tea.KeyCtrlC {
		return m, tea.Quit
	}
	if key.Type == tea.KeyRunes || key.Type == tea.KeySpace {
		runes := key.Runes
		if key.Type == tea.KeySpace {
			runes = []rune{' '}
		}
		for _, r := range runes {
			m.prompt, _, _ = applyKey(m.prompt, keyEvent{
				kind: keyPrintable,
				r:    r,
			})
		}
		return m, nil
	}
	if key.Type == tea.KeyBackspace || key.Type == tea.KeyCtrlH {
		m.prompt, _, _ = applyKey(m.prompt, keyEvent{kind: keyBackspace})
		return m, nil
	}
	if key.Type != tea.KeyEnter {
		return m, nil
	}

	nextPrompt, submitted, _ := applyKey(m.prompt, keyEvent{kind: keyEnter})
	m.prompt = nextPrompt
	if submitted == "" {
		return m, nil
	}

	resp, err := m.callbacks.Execute(submitted)
	if err != nil {
		m.message = err.Error()
		m.statusLine, m.morningPending = m.callbacks.StatusSnapshot()
		return m, nil
	}

	m.statusLine = resp.StatusLine
	m.morningPending = resp.MorningPending
	if resp.Error != "" {
		m.message = resp.Error
	} else if resp.Message != "" {
		m.message = resp.Message
	}
	if resp.Exit {
		return m, tea.Quit
	}
	return m, nil
}
