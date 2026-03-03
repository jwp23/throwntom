package main

import (
	"fmt"
	"io"

	tea "github.com/charmbracelet/bubbletea"
)

func runInteractiveTea(out io.Writer, in io.Reader, callbacks interactiveCallbacks) error {
	if callbacks.StatusSnapshot == nil || callbacks.Execute == nil {
		return fmt.Errorf("interactive callbacks must provide status snapshot and execute handlers")
	}

	model := newInteractiveTeaModel(callbacks)
	program := tea.NewProgram(
		model,
		tea.WithInput(in),
		tea.WithOutput(out),
	)
	_, err := program.Run()
	return err
}
