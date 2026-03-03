package main

type interactiveCallbacks struct {
	StatusSnapshot func() (string, bool)
	Execute        func(command string) (daemonControlResponse, error)
}
