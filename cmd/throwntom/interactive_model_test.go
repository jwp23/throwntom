package main

import "testing"

func TestApplyKeyPrintableAppendsRune(t *testing.T) {
	state := promptState{}

	state, submitted, ok := applyKey(state, keyEvent{kind: keyPrintable, r: 'a'})

	if !ok {
		t.Fatal("expected printable key to be handled")
	}
	if submitted != "" {
		t.Fatalf("expected no submission for printable key, got %q", submitted)
	}
	if state.input != "a" {
		t.Fatalf("expected input %q, got %q", "a", state.input)
	}
}

func TestApplyKeyBackspaceDeletesLastRune(t *testing.T) {
	state := promptState{input: "ab"}

	state, submitted, ok := applyKey(state, keyEvent{kind: keyBackspace})

	if !ok {
		t.Fatal("expected backspace key to be handled")
	}
	if submitted != "" {
		t.Fatalf("expected no submission for backspace key, got %q", submitted)
	}
	if state.input != "a" {
		t.Fatalf("expected input %q, got %q", "a", state.input)
	}
}

func TestApplyKeyEnterSubmitsAndClearsBuffer(t *testing.T) {
	state := promptState{input: "status"}

	state, submitted, ok := applyKey(state, keyEvent{kind: keyEnter})

	if !ok {
		t.Fatal("expected enter key to be handled")
	}
	if submitted != "status" {
		t.Fatalf("expected submitted command %q, got %q", "status", submitted)
	}
	if state.input != "" {
		t.Fatalf("expected cleared input after submit, got %q", state.input)
	}
}
