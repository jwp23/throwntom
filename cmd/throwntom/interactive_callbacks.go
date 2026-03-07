package main

import "github.com/jwp23/throwntom/v2/internal/engine"

type commandResponse struct {
	StatusLine     string
	EngineState    engine.State
	MorningPending bool
	Message        string
	Error          string
	Exit           bool
	FocusLines     []string
	FocusPrompt    string
}

type interactiveCallbacks struct {
	HeaderLines    []string
	HelpLines      []string
	Emoji          bool
	StatusSnapshot func() (string, engine.State, bool)
	FocusSnapshot  func() ([]string, string)
	Execute        func(command string) (commandResponse, error)
	CancelFocus    func() commandResponse
}
