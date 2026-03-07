package main

import (
	"bytes"
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v2/internal/engine"
)

func TestRunInteractiveTeaRequiresCallbacks(t *testing.T) {
	var out bytes.Buffer

	err := runInteractiveTea(&out, strings.NewReader(""), interactiveCallbacks{})
	if err == nil {
		t.Fatal("expected callback validation error")
	}
	if !strings.Contains(err.Error(), "interactive callbacks must provide status snapshot and execute handlers") {
		t.Fatalf("expected callback validation error, got %v", err)
	}
}

func TestRunInteractiveTeaCtrlCExitsWithoutExecute(t *testing.T) {
	var out bytes.Buffer
	executed := false

	err := runInteractiveTea(
		&out,
		strings.NewReader("\x03"),
		interactiveCallbacks{
			StatusSnapshot: func() (string, engine.State, bool) {
				return "Idle | 00:00", engine.Idle, false
			},
			Execute: func(string) (commandResponse, error) {
				executed = true
				return commandResponse{}, nil
			},
		},
	)
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if executed {
		t.Fatal("expected ctrl-c to exit without executing command")
	}
}
