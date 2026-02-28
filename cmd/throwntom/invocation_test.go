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
	if inv.controlCommand != "" {
		t.Fatalf("expected empty control command in run mode, got %q", inv.controlCommand)
	}
}

func TestParseInvocationModes(t *testing.T) {
	tests := []struct {
		name string
		args []string
		mode string
		cmd  string
	}{
		{name: "run explicit", args: []string{"run"}, mode: modeRun},
		{name: "daemon", args: []string{"daemon"}, mode: modeDaemon},
		{name: "shell", args: []string{"shell"}, mode: modeShell},
		{name: "ctl", args: []string{"ctl", "start"}, mode: modeControl, cmd: "start"},
		{name: "ctl with multiple words", args: []string{"ctl", "snooze", "10m"}, mode: modeControl, cmd: "snooze 10m"},
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
			if inv.controlCommand != tc.cmd {
				t.Fatalf("expected command %q, got %q", tc.cmd, inv.controlCommand)
			}
		})
	}
}

func TestParseInvocationErrors(t *testing.T) {
	tests := []struct {
		name string
		args []string
	}{
		{name: "ctl without command", args: []string{"ctl"}},
		{name: "unknown mode", args: []string{"wat"}},
		{name: "daemon with extra args", args: []string{"daemon", "extra"}},
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
