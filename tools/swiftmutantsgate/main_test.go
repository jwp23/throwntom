package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// violationsIn gates a single report, which is what the gate does for a run
// that needed only one. Merging across reports is exercised through run.
func violationsIn(data []byte, equivalents []equivalent) ([]violation, error) {
	merged := mutantSet{}
	if err := merged.add(data); err != nil {
		return nil, err
	}
	return findViolations(merged, equivalents), nil
}

func TestViolationsInAllKilledIsClean(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/Countdown.swift":{"mutants":[
		{"mutatorName":"RelationalOperatorReplacement","status":"Killed","location":{"start":{"line":10,"column":5}},"originalText":">","replacement":">="}
	]}}}`
	violations, err := violationsIn([]byte(report), nil)
	if err != nil {
		t.Fatalf("violationsIn: %v", err)
	}
	if len(violations) != 0 {
		t.Fatalf("violations = %v, want none", violations)
	}
}

// Unviable is absent: a mutant that does not compile cannot be killed by any
// test, so ADR-016 reports it without gating on it.
func TestViolationsInReportsEveryGatedStatus(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/Countdown.swift":{"mutants":[
		{"mutatorName":"RelationalOperatorReplacement","status":"Killed","location":{"start":{"line":10,"column":5}}},
		{"mutatorName":"RelationalOperatorReplacement","status":"Survived","location":{"start":{"line":11,"column":6}}},
		{"mutatorName":"BooleanLiteralReplacement","status":"Crash","location":{"start":{"line":12,"column":7}}},
		{"mutatorName":"NegateConditional","status":"Timeout","location":{"start":{"line":13,"column":8}}},
		{"mutatorName":"RemoveSideEffects","status":"Unviable","location":{"start":{"line":14,"column":9}}},
		{"mutatorName":"SwapTernary","status":"NoCoverage","location":{"start":{"line":15,"column":10}}}
	]}}}`
	violations, err := violationsIn([]byte(report), nil)
	if err != nil {
		t.Fatalf("violationsIn: %v", err)
	}
	got := map[string]bool{}
	for _, v := range violations {
		got[v.Status] = true
	}
	want := []string{"Survived", "Crash", "Timeout", "NoCoverage"}
	if len(violations) != len(want) {
		t.Fatalf("violations = %v, want %d (every gated status, Unviable excluded)", violations, len(want))
	}
	for _, status := range want {
		if !got[status] {
			t.Errorf("missing violation for status %q", status)
		}
	}
}

func TestViolationsInSortsByFileThenPosition(t *testing.T) {
	report := `{"files":{
		"Sources/ThrowntomUI/B.swift":{"mutants":[
			{"mutatorName":"M","status":"Survived","location":{"start":{"line":3,"column":1}}}
		]},
		"Sources/ThrowntomClient/A.swift":{"mutants":[
			{"mutatorName":"M","status":"Survived","location":{"start":{"line":9,"column":2}}},
			{"mutatorName":"M","status":"Survived","location":{"start":{"line":9,"column":1}}},
			{"mutatorName":"M","status":"Survived","location":{"start":{"line":2,"column":7}}}
		]}
	}}`
	violations, err := violationsIn([]byte(report), nil)
	if err != nil {
		t.Fatalf("violationsIn: %v", err)
	}
	sortViolations(violations)
	var got []string
	for _, v := range violations {
		got = append(got, v.String())
	}
	want := []string{
		"Sources/ThrowntomClient/A.swift:2:7 M Survived",
		"Sources/ThrowntomClient/A.swift:9:1 M Survived",
		"Sources/ThrowntomClient/A.swift:9:2 M Survived",
		"Sources/ThrowntomUI/B.swift:3:1 M Survived",
	}
	if strings.Join(got, "\n") != strings.Join(want, "\n") {
		t.Fatalf("order =\n%s\nwant\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
}

// One operator yields several mutants at one position, and the report is a
// map, so without a replacement tie-break the issue body reorders run to run.
func TestViolationsInOrdersSamePositionByReplacement(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","replacement":">=","location":{"start":{"line":3,"column":11}}},
		{"mutatorName":"M","status":"Survived","replacement":"<","location":{"start":{"line":3,"column":11}}}
	]}}}`
	violations, err := violationsIn([]byte(report), nil)
	if err != nil {
		t.Fatalf("violationsIn: %v", err)
	}
	sortViolations(violations)
	if len(violations) != 2 || violations[0].Replacement != "<" || violations[1].Replacement != ">=" {
		t.Fatalf("violations = %+v, want `<` before `>=`", violations)
	}
}

// violationsIn no longer sorts on its own; run sorts once after combining
// every report, so ordering doesn't depend on report or shard order.
func TestSortViolationsTieBreaksIdenticalPositionAndReplacement(t *testing.T) {
	violations := []violation{
		{File: "A.swift", Line: 1, Column: 1, Mutator: "Z", Replacement: "x", OriginalText: "b", Status: "Survived"},
		{File: "A.swift", Line: 1, Column: 1, Mutator: "A", Replacement: "x", OriginalText: "b", Status: "Survived"},
	}
	sortViolations(violations)
	if violations[0].Mutator != "A" || violations[1].Mutator != "Z" {
		t.Fatalf("violations = %+v, want Mutator A before Z", violations)
	}
}

func TestViolationsInRejectsMalformedJSON(t *testing.T) {
	if _, err := violationsIn([]byte("not json"), nil); err == nil {
		t.Fatal("expected an error for malformed JSON")
	}
}

// A report with no files or no mutants means the tool never mutated anything
// (wrong --sources-path, a crashed run), not that every mutant was killed.
func TestViolationsInRejectsReportWithNoFiles(t *testing.T) {
	if _, err := violationsIn([]byte(`{"files":{}}`), nil); err == nil {
		t.Fatal("expected an error for a report with no files")
	}
}

func TestViolationsInRejectsReportWithNoMutants(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[]}}}`
	if _, err := violationsIn([]byte(report), nil); err == nil {
		t.Fatal("expected an error for a report with no mutants")
	}
}

func TestViolationsInExcludesReviewedEquivalent(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"RelationalOperatorReplacement","status":"Survived","location":{"start":{"line":11,"column":6}}},
		{"mutatorName":"RelationalOperatorReplacement","status":"Survived","location":{"start":{"line":11,"column":7}}}
	]}}}`
	equivalents := []equivalent{{
		File: "Sources/ThrowntomClient/A.swift", Line: 11, Column: 6,
		Mutator: "RelationalOperatorReplacement", Reason: "proven equivalent",
	}}
	violations, err := violationsIn([]byte(report), equivalents)
	if err != nil {
		t.Fatalf("violationsIn: %v", err)
	}
	if len(violations) != 1 || violations[0].Column != 7 {
		t.Fatalf("violations = %v, want only the column-7 mutant", violations)
	}
}

func TestViolationsInEquivalentMustMatchMutator(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"NegateConditional","status":"Survived","location":{"start":{"line":11,"column":6}}}
	]}}}`
	equivalents := []equivalent{{
		File: "Sources/ThrowntomClient/A.swift", Line: 11, Column: 6,
		Mutator: "RelationalOperatorReplacement", Reason: "proven equivalent",
	}}
	violations, err := violationsIn([]byte(report), equivalents)
	if err != nil {
		t.Fatalf("violationsIn: %v", err)
	}
	if len(violations) != 1 {
		t.Fatalf("violations = %v, want the differently-mutated survivor kept", violations)
	}
}

// The tool keys files by the absolute path with the package root sliced off,
// which leaves a leading "/"; equivalents and output use the package-relative
// spelling a reader would type.
func TestViolationsInStripsLeadingSlashFromReportedFile(t *testing.T) {
	report := `{"files":{"/Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","replacement":">=","location":{"start":{"line":3,"column":11}}},
		{"mutatorName":"M","status":"Survived","replacement":"<","location":{"start":{"line":3,"column":11}}}
	]}}}`
	equivalents := []equivalent{{
		File: "Sources/ThrowntomClient/A.swift", Line: 3, Column: 11,
		Mutator: "M", Replacement: ">=", Reason: "proven equivalent",
	}}
	violations, err := violationsIn([]byte(report), equivalents)
	if err != nil {
		t.Fatalf("violationsIn: %v", err)
	}
	if len(violations) != 1 || violations[0].String() != "Sources/ThrowntomClient/A.swift:3:11 M Survived" {
		t.Fatalf("violations = %v, want only the unexcluded mutant, package-relative", violations)
	}
}

// One operator yields several mutants at the same position (`>` becomes both
// `>=` and `<`), so excluding one must not hide its siblings.
func TestViolationsInEquivalentMustMatchReplacement(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"RelationalOperatorReplacement","status":"Survived","originalText":">","replacement":"<","location":{"start":{"line":3,"column":11}}}
	]}}}`
	equivalents := []equivalent{{
		File: "Sources/ThrowntomClient/A.swift", Line: 3, Column: 11,
		Mutator: "RelationalOperatorReplacement", Replacement: ">=", Reason: "proven equivalent",
	}}
	violations, err := violationsIn([]byte(report), equivalents)
	if err != nil {
		t.Fatalf("violationsIn: %v", err)
	}
	if len(violations) != 1 {
		t.Fatalf("violations = %v, want the `<` survivor kept", violations)
	}
}

func TestLoadEquivalentsRejectsEmptyReason(t *testing.T) {
	path := filepath.Join(t.TempDir(), "equivalents.json")
	body := `[{"file":"Sources/ThrowntomClient/A.swift","line":1,"column":1,"mutator":"M","reason":"  "}]`
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := loadEquivalents(path); err == nil {
		t.Fatal("expected an error for an equivalent with a blank reason")
	}
}

func TestLoadEquivalentsEmptyPathMeansNone(t *testing.T) {
	equivalents, err := loadEquivalents("")
	if err != nil || equivalents != nil {
		t.Fatalf("loadEquivalents(\"\") = %v, %v; want nil, nil", equivalents, err)
	}
}

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
	if got := summarize(violations, 5); got != want {
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
	got := summarize(violations, 0)
	c := strings.Index(got, "Sources/C.swift")
	a := strings.Index(got, "Sources/A.swift")
	b := strings.Index(got, "Sources/B.swift")
	if c < 0 || a < 0 || b < 0 || c > a || a > b {
		t.Fatalf("want C (3), then A and B (2 each, by path):\n%s", got)
	}
}

func TestSummarizeCleanRunSaysSo(t *testing.T) {
	if got, want := summarize(nil, 0), "No unexcluded mutants survived.\n"; got != want {
		t.Fatalf("summarize(nil, 0) = %q, want %q", got, want)
	}
	want := "No unexcluded mutants survived.\n" +
		"\n" +
		"2 Unviable mutant(s) not gated (ADR-016): they do not compile, so no test can kill them.\n"
	if got := summarize(nil, 2); got != want {
		t.Fatalf("summarize(nil, 2) = %q, want %q", got, want)
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

// A triage pass scopes the tool more than one way, so the same mutant is
// reported twice, and the two verdicts can disagree: the pinned tool SIGKILLs
// whichever test run is in flight five seconds after a mutant times out, so a
// run containing a Timeout can report a killed mutant as Crash. Reports are
// merged by mutant identity, keeping the verdict from the fullest observation.
func TestRunKeepsTheBestVerdictForAMutantSeenTwice(t *testing.T) {
	poisoned := writeReport(t, `{"files":{"/Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"RemoveSideEffects","status":"Timeout","location":{"start":{"line":146,"column":5}},"originalText":"lock.unlock()","replacement":""},
		{"mutatorName":"NegateConditional","status":"Crash","location":{"start":{"line":147,"column":8}},"originalText":"wasCancelled","replacement":"!(wasCancelled)"}
	]}}}`)
	clean := writeReport(t, `{"files":{"/Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"NegateConditional","status":"Killed","location":{"start":{"line":147,"column":8}},"originalText":"wasCancelled","replacement":"!(wasCancelled)"}
	]}}}`)
	var stdout, stderr bytes.Buffer
	code := run([]string{poisoned, clean}, "", "", &stdout, &stderr)
	if strings.Contains(stdout.String(), "A.swift:147:8") {
		t.Fatalf("the Crash was not corrected by the run that killed it:\n%s", stdout.String())
	}
	if code != 1 || !strings.Contains(stdout.String(), "A.swift:146:5") {
		t.Fatalf("exit = %d, want 1 with the Timeout still gated:\n%s", code, stdout.String())
	}
}

// Neither verdict is a kill, so the gate fails either way — but the status it
// prints is the one a run actually observed, not the one a SIGKILL invented.
func TestRunPrefersACompletedRunOverACrash(t *testing.T) {
	poisoned := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Timeout","location":{"start":{"line":1,"column":1}}},
		{"mutatorName":"M","status":"Crash","location":{"start":{"line":9,"column":2}}}
	]}}}`)
	clean := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","location":{"start":{"line":9,"column":2}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{poisoned, clean}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1; stderr=%s", code, stderr.String())
	}
	if strings.Count(stdout.String(), "A.swift:9:2") != 1 {
		t.Fatalf("want one line for the mutant, not one per report:\n%s", stdout.String())
	}
	if !strings.Contains(stdout.String(), "A.swift:9:2` M Survived") {
		t.Fatalf("want the completed run's verdict, not the Crash:\n%s", stdout.String())
	}
}

// Unviable is the one ungated status the tool reports for a run that produced
// no test output at all, which is also what a run SIGKILLed before its tests
// started looks like. A kill anywhere beats it, and the mutant is then not
// counted as Unviable either.
func TestRunKeepsAKillOverUnviable(t *testing.T) {
	first := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Unviable","location":{"start":{"line":1,"column":1}}}
	]}}}`)
	second := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":1,"column":1}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{first, second}, "", "", &stdout, &stderr); code != 0 {
		t.Fatalf("exit = %d, want 0; stdout=%s stderr=%s", code, stdout.String(), stderr.String())
	}
	if strings.Contains(stdout.String(), "Unviable mutant(s)") {
		t.Fatalf("a killed mutant is not an Unviable one:\n%s", stdout.String())
	}
}

// Overlapping scopes report the same Unviable mutant more than once; counting
// it per report would inflate the figure the tracking issue carries.
func TestRunCountsAMutantSeenTwiceOnce(t *testing.T) {
	body := `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Unviable","location":{"start":{"line":1,"column":1}}},
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":2,"column":1}}}
	]}}}`
	first := writeReport(t, body)
	second := writeReport(t, body)
	var stdout, stderr bytes.Buffer
	if code := run([]string{first, second}, "", "", &stdout, &stderr); code != 0 {
		t.Fatalf("exit = %d, want 0; stdout=%s stderr=%s", code, stdout.String(), stderr.String())
	}
	if !strings.Contains(stdout.String(), "1 Unviable mutant(s) not gated") {
		t.Fatalf("want the mutant counted once across both reports:\n%s", stdout.String())
	}
}

// One operator yields several mutants at one position, telling them apart only
// by replacement; merging those would hide a survivor behind its sibling's kill.
func TestRunDoesNotMergeDistinctReplacementsAtOnePosition(t *testing.T) {
	report := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Killed","originalText":">","replacement":">=","location":{"start":{"line":3,"column":11}}},
		{"mutatorName":"M","status":"Survived","originalText":">","replacement":"<","location":{"start":{"line":3,"column":11}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{report}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1; stdout=%s", code, stdout.String())
	}
	if !strings.Contains(stdout.String(), "<code>&lt;</code>") {
		t.Fatalf("the `<` survivor was merged into its killed sibling:\n%s", stdout.String())
	}
}

// A Crash from a run that also timed a mutant out may be the tool's doing
// rather than the mutant's, and the gate is where both are visible at once.
func TestRunFlagsCrashesFromARunThatAlsoTimedOut(t *testing.T) {
	poisoned := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Timeout","location":{"start":{"line":1,"column":1}}},
		{"mutatorName":"M","status":"Crash","location":{"start":{"line":9,"column":2}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{poisoned}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1; stderr=%s", code, stderr.String())
	}
	want := "- `Sources/ThrowntomClient/A.swift:9:2` M Crash — reported Crash only by a run that also timed a mutant out"
	if !strings.Contains(stdout.String(), want) {
		t.Fatalf("stdout does not name the suspect Crash:\n%s", stdout.String())
	}
}

// A Crash is loud — it fails the gate on its own. An Unviable is the silent
// half of the same defect: a run SIGKILLed before its first test marker is
// reported Unviable, which the gate lets through, so a live mutant can pass as
// one that does not compile. It gets the same note.
func TestRunFlagsAnUnviableSeenOnlyInARunThatTimedOut(t *testing.T) {
	poisoned := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Timeout","location":{"start":{"line":1,"column":1}}},
		{"mutatorName":"M","status":"Unviable","location":{"start":{"line":9,"column":2}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{poisoned}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1 (the Timeout is gated); stderr=%s", code, stderr.String())
	}
	want := "- `Sources/ThrowntomClient/A.swift:9:2` M Unviable — reported Unviable only by a run that also timed a mutant out"
	if !strings.Contains(stdout.String(), want) {
		t.Fatalf("stdout does not name the suspect Unviable:\n%s", stdout.String())
	}
}

// A mutant that does not compile does not compile in every run. Once a run that
// timed nothing out has said Unviable too, the verdict is the mutant's own.
func TestRunDoesNotFlagAnUnviableATimeoutFreeRunConfirms(t *testing.T) {
	poisoned := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Timeout","location":{"start":{"line":1,"column":1}}},
		{"mutatorName":"M","status":"Unviable","location":{"start":{"line":9,"column":2}}}
	]}}}`)
	clean := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Unviable","location":{"start":{"line":9,"column":2}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{poisoned, clean}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1 (the Timeout is gated); stderr=%s", code, stderr.String())
	}
	if strings.Contains(stdout.String(), "do not settle") {
		t.Fatalf("a verdict two runs agree on is settled:\n%s", stdout.String())
	}
	if !strings.Contains(stdout.String(), "1 Unviable mutant(s) not gated") {
		t.Fatalf("stdout lost the Unviable count:\n%s", stdout.String())
	}
}

// The one disagreement no merge rule can resolve. Poisoning cannot produce a
// Survived — a SIGKILLed run exits non-zero — so this is a flaky or
// order-dependent test, and the kill the gate keeps may be the wrong half. The
// gate says so out loud rather than exiting 0 in silence.
func TestRunFlagsAKillAnotherRunDisagreedWith(t *testing.T) {
	killed := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":3,"column":1}}}
	]}}}`)
	survived := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","location":{"start":{"line":3,"column":1}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{killed, survived}, "", "", &stdout, &stderr); code != 0 {
		t.Fatalf("exit = %d, want 0: the gate keeps the kill; stderr=%s", code, stderr.String())
	}
	want := "- `Sources/ThrowntomClient/A.swift:3:1` M Killed — reported Killed by one run and Survived by another; the gate keeps the kill"
	if !strings.Contains(stdout.String(), want) {
		t.Fatalf("a laundered kill passed in silence:\n%s", stdout.String())
	}
}

// Two runs that agree have nothing to settle, however many reports say Killed.
func TestRunDoesNotFlagAKillNoRunDisagreedWith(t *testing.T) {
	first := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Timeout","location":{"start":{"line":1,"column":1}}},
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":3,"column":1}}}
	]}}}`)
	second := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":3,"column":1}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{first, second}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1 (the Timeout is gated); stderr=%s", code, stderr.String())
	}
	if strings.Contains(stdout.String(), "do not settle") {
		t.Fatalf("nothing disagreed:\n%s", stdout.String())
	}
}

// A reviewed equivalent rests on a written reason, not on a verdict, so it is
// not something a second run is asked to settle.
func TestRunDoesNotFlagAReviewedEquivalent(t *testing.T) {
	poisoned := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Timeout","location":{"start":{"line":1,"column":1}}},
		{"mutatorName":"M","status":"Crash","location":{"start":{"line":9,"column":2}}}
	]}}}`)
	path := filepath.Join(t.TempDir(), "equivalents.json")
	body := `[{"file":"Sources/ThrowntomClient/A.swift","line":9,"column":2,"mutator":"M","reason":"proven equivalent"}]`
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	if code := run([]string{poisoned}, path, "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1 (the Timeout is gated); stderr=%s", code, stderr.String())
	}
	if strings.Contains(stdout.String(), "A.swift:9:2") {
		t.Fatalf("an excluded mutant came back through the note:\n%s", stdout.String())
	}
}

// Unviable is one of the two verdicts the gate lets through, so it must lose
// every merge it takes part in — including one against a status this gate does
// not recognise, which a later version of the tool could introduce.
func TestRunNeverLetsUnviableDisplaceAnotherVerdict(t *testing.T) {
	unknown := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Rescheduled","location":{"start":{"line":3,"column":1}}}
	]}}}`)
	unviable := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Unviable","location":{"start":{"line":3,"column":1}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{unviable, unknown}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1: an unrecognised verdict is gated; stdout=%s", code, stdout.String())
	}
	if !strings.Contains(stdout.String(), "A.swift:3:1` M Rescheduled") {
		t.Fatalf("Unviable displaced the verdict the gate could not read:\n%s", stdout.String())
	}
}

// Once a timeout-free run has reported the same mutant, the Crash is gone and
// so is the doubt; a note that never clears is one nobody reads.
func TestRunDoesNotFlagACrashAlreadyCorrected(t *testing.T) {
	poisoned := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Timeout","location":{"start":{"line":1,"column":1}}},
		{"mutatorName":"M","status":"Crash","location":{"start":{"line":9,"column":2}}}
	]}}}`)
	clean := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":9,"column":2}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{poisoned, clean}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1 (the Timeout is still gated); stderr=%s", code, stderr.String())
	}
	if strings.Contains(stdout.String(), "do not settle") {
		t.Fatalf("the note outlived the Crash it was about:\n%s", stdout.String())
	}
}

// A Crash in a run that timed nothing out is the mutant's own doing.
func TestRunDoesNotFlagACrashFromATimeoutFreeRun(t *testing.T) {
	report := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Crash","location":{"start":{"line":9,"column":2}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{report}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1; stderr=%s", code, stderr.String())
	}
	if strings.Contains(stdout.String(), "do not settle") {
		t.Fatalf("nothing timed out, so nothing is suspect:\n%s", stdout.String())
	}
}
