package main

import (
	"os"
	"strings"
	"testing"
)

func TestServiceTemplatesExistForSystemdAndLaunchd(t *testing.T) {
	tests := []struct {
		path     string
		expected []string
	}{
		{
			path: "../../packaging/systemd/throwntom.service",
			expected: []string{
				"[Unit]",
				"[Service]",
				"[Install]",
				"throwntom daemon",
			},
		},
		{
			path: "../../packaging/launchd/io.github.jwp23.throwntom.plist",
			expected: []string{
				"<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
				"<plist version=\"1.0\">",
				"throwntom",
				"daemon",
			},
		},
	}

	for _, tc := range tests {
		tc := tc
		t.Run(tc.path, func(t *testing.T) {
			b, err := os.ReadFile(tc.path)
			if err != nil {
				t.Fatalf("read template %s: %v", tc.path, err)
			}
			content := string(b)
			for _, want := range tc.expected {
				if !strings.Contains(content, want) {
					t.Fatalf("expected %q in template %s", want, tc.path)
				}
			}
		})
	}
}
