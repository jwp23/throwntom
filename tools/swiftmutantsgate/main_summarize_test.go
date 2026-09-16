package main

import (
	"strings"
	"testing"
)

// The tracking issue body holds this summary: GitHub caps a body at 65,536
// characters, and the full per-mutant list (630 mutants, 112,339 characters in
// the first sharded run) does not fit, while a row per file does.
func TestSummarizeGroupsByFileWithCountsAndStatuses(t *testing.T) {
	violations := []violation{
		{File: "Sources/A.swift", Line: 1, Column: 1, Mutator: "M", Status: "Survived"},
		{File: "Sources/A.swift", Line: 2, Column: 1, Mutator: "M", Status: "Crash"},
		{File: "Sources/A.swift", Line: 3, Column: 1, Mutator: "M", Status: "Survived"},
		{File: "Sources/B.swift", Line: 1, Column: 1, Mutator: "M", Status: "Timeout"},
	}
	want := "4 unexcluded mutant(s) not killed in 2 file(s).\n" +
		"\n" +
		"| File | Gated | Statuses |\n" +
		"|---|---|---|\n" +
		"| `Sources/A.swift` | 3 | Crash 1, Survived 2 |\n" +
		"| `Sources/B.swift` | 1 | Timeout 1 |\n" +
		"\n" +
		"5 Unviable mutant(s) not gated (ADR-016): they do not compile, so no test can kill them.\n"
	if got := summarize(violations, 5, nil); got != want {
		t.Fatalf("summarize =\n%s\nwant\n%s", got, want)
	}
}

// Heaviest files first so the triage priority reads top-down; ties by path so
// the body is identical week to week for identical results.
func TestSummarizeOrdersFilesByGatedCountThenPath(t *testing.T) {
	violations := []violation{
		{File: "Sources/B.swift", Status: "Survived"},
		{File: "Sources/B.swift", Status: "Survived"},
		{File: "Sources/C.swift", Status: "Survived"},
		{File: "Sources/C.swift", Status: "Survived"},
		{File: "Sources/C.swift", Status: "Survived"},
		{File: "Sources/A.swift", Status: "Survived"},
		{File: "Sources/A.swift", Status: "Survived"},
	}
	got := summarize(violations, 0, nil)
	c := strings.Index(got, "Sources/C.swift")
	a := strings.Index(got, "Sources/A.swift")
	b := strings.Index(got, "Sources/B.swift")
	if c < 0 || a < 0 || b < 0 || c > a || a > b {
		t.Fatalf("want C (3), then A and B (2 each, by path):\n%s", got)
	}
}

func TestSummarizeCleanRunSaysSo(t *testing.T) {
	if got, want := summarize(nil, 0, nil), "No unexcluded mutants survived.\n"; got != want {
		t.Fatalf("summarize(nil, 0) = %q, want %q", got, want)
	}
	want := "No unexcluded mutants survived.\n" +
		"\n" +
		"2 Unviable mutant(s) not gated (ADR-016): they do not compile, so no test can kill them.\n"
	if got := summarize(nil, 2, nil); got != want {
		t.Fatalf("summarize(nil, 2) = %q, want %q", got, want)
	}
}
