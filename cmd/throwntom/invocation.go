package main

import (
	"fmt"
	"strings"
)

const (
	modeRun     = "run"
	modeDaemon  = "daemon"
	modeShell   = "shell"
	modeControl = "ctl"
)

type invocation struct {
	mode           string
	controlCommand string
}

func parseInvocation(args []string) (invocation, error) {
	if len(args) == 0 {
		return invocation{mode: modeRun}, nil
	}

	mode := args[0]
	rest := args[1:]

	switch mode {
	case modeRun, modeDaemon, modeShell:
		if len(rest) != 0 {
			return invocation{}, fmt.Errorf("mode %q does not accept positional args: %v", mode, rest)
		}
		return invocation{mode: mode}, nil
	case modeControl:
		if len(rest) == 0 {
			return invocation{}, fmt.Errorf("mode %q requires a command", modeControl)
		}
		return invocation{
			mode:           modeControl,
			controlCommand: strings.Join(rest, " "),
		}, nil
	default:
		return invocation{}, fmt.Errorf("unknown mode %q", mode)
	}
}
