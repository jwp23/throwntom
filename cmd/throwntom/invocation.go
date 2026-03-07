package main

import "fmt"

func parseInvocation(args []string) error {
	if len(args) != 0 {
		return fmt.Errorf("unexpected positional arguments: %v", args)
	}
	return nil
}
