package main

type interactiveCallbacks struct {
	HeaderLines    []string
	StatusSnapshot func() (string, bool)
	Execute        func(command string) (daemonControlResponse, error)
}
