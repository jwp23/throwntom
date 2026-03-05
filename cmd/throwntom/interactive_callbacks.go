package main

type daemonControlResponse struct {
	StatusLine     string
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
	StatusSnapshot func() (string, bool)
	FocusSnapshot  func() ([]string, string)
	Execute        func(command string) (daemonControlResponse, error)
	CancelFocus    func() daemonControlResponse
}
