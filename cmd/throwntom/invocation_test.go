package main

import "testing"

func TestParseInvocationNoArgs(t *testing.T) {
	if err := parseInvocation(nil); err != nil {
		t.Fatalf("expected no error for nil args: %v", err)
	}
}

func TestParseInvocationRejectsPositionalArgs(t *testing.T) {
	tests := []struct {
		name string
		args []string
	}{
		{name: "single arg", args: []string{"run"}},
		{name: "unknown arg", args: []string{"wat"}},
		{name: "multiple args", args: []string{"run", "extra"}},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			if parseInvocation(tc.args) == nil {
				t.Fatalf("expected error for args %v", tc.args)
			}
		})
	}
}
