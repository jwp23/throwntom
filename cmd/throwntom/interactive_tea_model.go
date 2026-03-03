package main

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

type interactiveTickMsg struct{}

type interactiveTeaModel struct {
	callbacks      interactiveCallbacks
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
		if msg.Width < 0 {
			msg.Width = 0
		}
		m.width = msg.Width
		return m, nil
	default:
		return m, nil
	}
}

func (m interactiveTeaModel) View() string {
	return renderFrameWithWidth(m.statusLine, m.morningPending, m.message, m.prompt.input, m.width)
}

func (m interactiveTeaModel) updateKey(key tea.KeyMsg) (tea.Model, tea.Cmd) {
	if key.Type == tea.KeyCtrlC {
		return m, tea.Quit
	}
	if key.Type == tea.KeyRunes {
		for _, r := range key.Runes {
			var handled bool
			m.prompt, _, handled = applyKey(m.prompt, keyEvent{
				kind: keyPrintable,
				r:    r,
			})
			if !handled {
				return m, nil
			}
		}
		return m, nil
	}
	if key.Type == tea.KeyBackspace || key.Type == tea.KeyCtrlH {
		var handled bool
		m.prompt, _, handled = applyKey(m.prompt, keyEvent{kind: keyBackspace})
		if !handled {
			return m, nil
		}
		return m, nil
	}
	if key.Type != tea.KeyEnter {
		return m, nil
	}

	nextPrompt, submitted, handled := applyKey(m.prompt, keyEvent{kind: keyEnter})
	if !handled {
		return m, nil
	}
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
