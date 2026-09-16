package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeReport(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "report.json")
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestRunCombinesReportsAndFailsOnAnyViolation(t *testing.T) {
	clean := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":1,"column":1}}}
	]}}}`)
	dirty := writeReport(t, `{"files":{"Sources/ThrowntomUI/B.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","location":{"start":{"line":4,"column":2}},"originalText":">","replacement":">="}
	]}}}`)
	var stdout, stderr bytes.Buffer
	code := run([]string{clean, dirty}, "", "", &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit = %d, want 1; stderr=%s", code, stderr.String())
	}
	if !strings.Contains(stdout.String(), "- `Sources/ThrowntomUI/B.swift:4:2` M Survived (<code>&gt;</code> → <code>&gt;=</code>)") {
		t.Fatalf("stdout missing the survivor line:\n%s", stdout.String())
	}
}

// OriginalText and Replacement come from mutated source and can contain
// backticks or newlines; rendering them as Markdown would split a mutant
// across lines or corrupt the tracking issue body.
func TestRunEscapesMutationTextForMarkdown(t *testing.T) {
	body := "{\"files\":{\"Sources/ThrowntomUI/B.swift\":{\"mutants\":[\n" +
		"\t\t{\"mutatorName\":\"M\",\"status\":\"Survived\",\"location\":{\"start\":{\"line\":4,\"column\":2}},\"originalText\":\"a`b\\nc\",\"replacement\":\"<x>\"}\n" +
		"\t]}}}"
	report := writeReport(t, body)
	var stdout, stderr bytes.Buffer
	if code := run([]string{report}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1; stderr=%s", code, stderr.String())
	}
	if strings.Contains(stdout.String(), "a`b\nc") {
		t.Fatalf("stdout embeds raw mutant text unescaped:\n%s", stdout.String())
	}
	if !strings.Contains(stdout.String(), "<code>a`b\\nc</code> → <code>&lt;x&gt;</code>") {
		t.Fatalf("stdout missing escaped mutant text:\n%s", stdout.String())
	}
}

// Shards are passed in matrix order, not file order, so run must sort across
// reports or the tracking issue reorders whenever shard membership shifts.
func TestRunOrdersViolationsAcrossReports(t *testing.T) {
	later := writeReport(t, `{"files":{"Sources/ThrowntomUI/Z.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","location":{"start":{"line":1,"column":1}}}
	]}}}`)
	earlier := writeReport(t, `{"files":{"Sources/ThrowntomUI/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","location":{"start":{"line":1,"column":1}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{later, earlier}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1; stderr=%s", code, stderr.String())
	}
	out := stdout.String()
	a := strings.Index(out, "Sources/ThrowntomUI/A.swift")
	z := strings.Index(out, "Sources/ThrowntomUI/Z.swift")
	if a < 0 || z < 0 || a > z {
		t.Fatalf("want A.swift listed before Z.swift regardless of report order:\n%s", out)
	}
}

func TestRunOnlyUnviableIsCleanButCounted(t *testing.T) {
	first := writeReport(t, `{"files":{"Sources/ThrowntomUI/A.swift":{"mutants":[
		{"mutatorName":"RemoveSideEffects","status":"Unviable","location":{"start":{"line":1,"column":1}}},
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":2,"column":1}}}
	]}}}`)
	second := writeReport(t, `{"files":{"Sources/ThrowntomUI/B.swift":{"mutants":[
		{"mutatorName":"SwapTernary","status":"Unviable","location":{"start":{"line":1,"column":1}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{first, second}, "", "", &stdout, &stderr); code != 0 {
		t.Fatalf("exit = %d, want 0; stdout=%s stderr=%s", code, stdout.String(), stderr.String())
	}
	if !strings.Contains(stdout.String(), "2 Unviable mutant(s) not gated") {
		t.Fatalf("stdout missing the Unviable count across both reports:\n%s", stdout.String())
	}
}

func TestRunViolationsAlsoCountUnviable(t *testing.T) {
	report := writeReport(t, `{"files":{"Sources/ThrowntomUI/A.swift":{"mutants":[
		{"mutatorName":"RemoveSideEffects","status":"Unviable","location":{"start":{"line":1,"column":1}}},
		{"mutatorName":"M","status":"Survived","location":{"start":{"line":2,"column":1}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{report}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1", code)
	}
	if !strings.Contains(stdout.String(), "1 Unviable mutant(s) not gated") {
		t.Fatalf("stdout missing the Unviable count:\n%s", stdout.String())
	}
}

func TestRunCleanReportsExitZero(t *testing.T) {
	clean := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":1,"column":1}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{clean}, "", "", &stdout, &stderr); code != 0 {
		t.Fatalf("exit = %d, want 0; stdout=%s stderr=%s", code, stdout.String(), stderr.String())
	}
}

// One unreadable report must fail the gate even when the others are clean:
// a target whose run never produced a report has not been shown clean. It
// exits 2, not 1, so the weekly workflow can tell a broken run from survivors.
func TestRunMissingReportIsAnErrorNotSurvivors(t *testing.T) {
	clean := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":1,"column":1}}}
	]}}}`)
	missing := filepath.Join(t.TempDir(), "absent.json")
	var stdout, stderr bytes.Buffer
	if code := run([]string{clean, missing}, "", "", &stdout, &stderr); code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
}

func TestRunUnreadableEquivalentsIsAnError(t *testing.T) {
	clean := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":1,"column":1}}}
	]}}}`)
	missing := filepath.Join(t.TempDir(), "absent-equivalents.json")
	var stdout, stderr bytes.Buffer
	if code := run([]string{clean}, missing, "", &stdout, &stderr); code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
}

func TestRunWritesSummaryAndKeepsFullListOnStdout(t *testing.T) {
	report := writeReport(t, `{"files":{"Sources/ThrowntomUI/B.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","location":{"start":{"line":4,"column":2}}},
		{"mutatorName":"M","status":"Unviable","location":{"start":{"line":5,"column":2}}}
	]}}}`)
	summaryPath := filepath.Join(t.TempDir(), "summary.md")
	var stdout, stderr bytes.Buffer
	if code := run([]string{report}, "", summaryPath, &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1; stderr=%s", code, stderr.String())
	}
	if !strings.Contains(stdout.String(), "- `Sources/ThrowntomUI/B.swift:4:2` M Survived") {
		t.Fatalf("stdout lost the per-mutant line:\n%s", stdout.String())
	}
	data, err := os.ReadFile(summaryPath)
	if err != nil {
		t.Fatalf("summary not written: %v", err)
	}
	want := "1 unexcluded mutant(s) not killed in 1 file(s).\n" +
		"\n" +
		"| File | Gated | Statuses |\n" +
		"|---|---|---|\n" +
		"| `Sources/ThrowntomUI/B.swift` | 1 | Survived 1 |\n" +
		"\n" +
		"1 Unviable mutant(s) not gated (ADR-016): they do not compile, so no test can kill them.\n"
	if string(data) != want {
		t.Fatalf("summary =\n%s\nwant\n%s", data, want)
	}
}

// The tracking issue body is summary.md, not stdout — an unsettled verdict
// that only reached stdout would never surface there, hiding a timeout-poisoned
// or contradictory report from the one place triage actually reads.
func TestRunWritesUnsettledVerdictsIntoSummary(t *testing.T) {
	poisoned := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Timeout","location":{"start":{"line":1,"column":1}}},
		{"mutatorName":"M","status":"Crash","location":{"start":{"line":9,"column":2}}}
	]}}}`)
	summaryPath := filepath.Join(t.TempDir(), "summary.md")
	var stdout, stderr bytes.Buffer
	if code := run([]string{poisoned}, "", summaryPath, &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1; stderr=%s", code, stderr.String())
	}
	data, err := os.ReadFile(summaryPath)
	if err != nil {
		t.Fatalf("summary not written: %v", err)
	}
	if !strings.Contains(string(data), "reported Crash only by a run that also timed a mutant out") {
		t.Fatalf("summary lost the unsettled verdict:\n%s", data)
	}
}

// A summary that cannot be written would leave the workflow filing an empty or
// stale issue body, so it is an error, not a quiet success.
func TestRunUnwritableSummaryIsAnError(t *testing.T) {
	report := writeReport(t, `{"files":{"Sources/ThrowntomUI/B.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","location":{"start":{"line":4,"column":2}}}
	]}}}`)
	summaryPath := filepath.Join(t.TempDir(), "missing-dir", "summary.md")
	var stdout, stderr bytes.Buffer
	if code := run([]string{report}, "", summaryPath, &stdout, &stderr); code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
}
