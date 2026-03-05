package main

import "fmt"

const modeRun = "run"

type invocation struct {
	mode string
}

func parseInvocation(args []string) (invocation, error) {
	if len(args) == 0 {
		return invocation{mode: modeRun}, nil
	}

	mode := args[0]
	rest := args[1:]

	switch mode {
	case modeRun:
		if len(rest) != 0 {
			return invocation{}, fmt.Errorf("mode %q does not accept positional args: %v", mode, rest)
		}
		return invocation{mode: modeRun}, nil
	default:
		return invocation{}, fmt.Errorf("unknown mode %q", mode)
	}
}
