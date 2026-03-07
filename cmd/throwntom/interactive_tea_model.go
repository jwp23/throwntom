package main

import (
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/jwp23/throwntom/v2/internal/engine"
)

type interactiveTickMsg struct{}

type interactiveTeaModel struct {
	callbacks      interactiveCallbacks
	headerLines    []string
	helpLines      []string
	showHelp       bool
	statusLine     string
	engineState    engine.State
	morningPending bool
	isError        bool
	emoji          bool
	message        string
	prompt         promptState
	width          int
	focusLines     []string
	focusPrompt    string
}

func newInteractiveTeaModel(callbacks interactiveCallbacks) interactiveTeaModel {
	statusLine, engineState, morningPending := callbacks.StatusSnapshot()
	return interactiveTeaModel{
		callbacks:      callbacks,
		headerLines:    append([]string(nil), callbacks.HeaderLines...),
		helpLines:      append([]string(nil), callbacks.HelpLines...),
		statusLine:     statusLine,
		engineState:    engineState,
		morningPending: morningPending,
		emoji:          callbacks.Emoji,
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
		m.statusLine, m.engineState, m.morningPending = m.callbacks.StatusSnapshot()
		if m.callbacks.FocusSnapshot != nil {
			m.focusLines, m.focusPrompt = m.callbacks.FocusSnapshot()
		}
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
	if m.focusPrompt != "" {
		var lines []string
		for _, line := range strings.Split(m.focusPrompt, "\n") {
			lines = append(lines, clampANSILine(line, m.width))
		}
		lines = append(lines, clampANSILine("> "+m.prompt.input, m.width))
		return strings.Join(lines, "\n")
	}

	frame := renderThemedFrame(frameInput{
		StatusLine:     m.statusLine,
		State:          m.engineState,
		MorningPending: m.morningPending,
		Message:        m.message,
		IsError:        m.isError,
		Input:          m.prompt.input,
		Width:          m.width,
		Emoji:          m.emoji,
	})

	var header []string
	for _, line := range m.headerLines {
		header = append(header, clampANSILine(line, m.width))
	}
	for _, line := range m.focusLines {
		header = append(header, clampANSILine(line, m.width))
	}
	if m.showHelp {
		for _, line := range m.helpLines {
			header = append(header, clampANSILine(line, m.width))
		}
	} else if len(m.helpLines) > 0 {
		header = append(header, clampANSILine("?: help", m.width))
	}

	if len(header) == 0 {
		return frame
	}
	return strings.Join(append(header, frame), "\n")
}

func (m interactiveTeaModel) updateKey(key tea.KeyMsg) (tea.Model, tea.Cmd) {
	if key.Type == tea.KeyCtrlC {
		return m, tea.Quit
	}
	if key.Type == tea.KeyEsc {
		return m.handleEsc()
	}
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
	if key.Type == tea.KeyBackspace || key.Type == tea.KeyCtrlH {
		m.prompt, _, _ = applyKey(m.prompt, keyEvent{kind: keyBackspace})
		return m, nil
	}
	if key.Type != tea.KeyEnter {
		return m, nil
	}
	return m.submitCommand()
}

func (m interactiveTeaModel) handleEsc() (tea.Model, tea.Cmd) {
	if m.focusPrompt != "" && m.callbacks.CancelFocus != nil {
		resp := m.callbacks.CancelFocus()
		m.focusPrompt = ""
		m.focusLines = resp.FocusLines
		m.statusLine = resp.StatusLine
		m.engineState = resp.EngineState
		m.morningPending = resp.MorningPending
		if resp.Message != "" {
			m.message = resp.Message
		}
		m.prompt = promptState{}
	}
	return m, nil
}

func (m interactiveTeaModel) submitCommand() (tea.Model, tea.Cmd) {
	nextPrompt, submitted, _ := applyKey(m.prompt, keyEvent{kind: keyEnter})
	m.prompt = nextPrompt
	if submitted == "" && m.focusPrompt == "" {
		return m, nil
	}

	resp, err := m.callbacks.Execute(submitted)
	if err != nil {
		m.message = err.Error()
		m.isError = true
		m.statusLine, m.engineState, m.morningPending = m.callbacks.StatusSnapshot()
		return m, nil
	}

	m.statusLine = resp.StatusLine
	m.engineState = resp.EngineState
	m.morningPending = resp.MorningPending
	m.focusLines = resp.FocusLines
	m.focusPrompt = resp.FocusPrompt
	if resp.Error != "" {
		m.message = resp.Error
		m.isError = true
	} else if resp.Message != "" {
		m.message = resp.Message
		m.isError = false
	}
	if resp.Exit {
		return m, tea.Quit
	}
	return m, nil
}
