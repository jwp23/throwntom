package main

type interactiveCallbacks struct {
	HeaderLines    []string
	HelpLines      []string
	StatusSnapshot func() (string, bool)
	FocusSnapshot  func() ([]string, string)
	Execute        func(command string) (daemonControlResponse, error)
}
