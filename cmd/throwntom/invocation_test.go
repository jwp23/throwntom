package main

import "testing"

func TestParseInvocationDefaultsToRunMode(t *testing.T) {
	inv, err := parseInvocation(nil)
	if err != nil {
		t.Fatalf("parse invocation: %v", err)
	}
	if inv.mode != modeRun {
		t.Fatalf("expected %q mode, got %q", modeRun, inv.mode)
	}
}

func TestParseInvocationModes(t *testing.T) {
	tests := []struct {
		name string
		args []string
		mode string
	}{
		{name: "run explicit", args: []string{"run"}, mode: modeRun},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			inv, err := parseInvocation(tc.args)
			if err != nil {
				t.Fatalf("parse invocation: %v", err)
			}
			if inv.mode != tc.mode {
				t.Fatalf("expected %q mode, got %q", tc.mode, inv.mode)
			}
		})
	}
}

func TestParseInvocationErrors(t *testing.T) {
	tests := []struct {
		name string
		args []string
	}{
		{name: "unknown mode", args: []string{"wat"}},
		{name: "run with extra args", args: []string{"run", "extra"}},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			if _, err := parseInvocation(tc.args); err == nil {
				t.Fatalf("expected parse error for args %v", tc.args)
			}
		})
	}
}
