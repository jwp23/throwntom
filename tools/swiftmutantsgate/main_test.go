package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFindViolationsAllKilledIsClean(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/Countdown.swift":{"mutants":[
		{"mutatorName":"RelationalOperatorReplacement","status":"Killed","location":{"start":{"line":10,"column":5}},"originalText":">","replacement":">="}
	]}}}`
	violations, err := findViolations([]byte(report), nil)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
	}
	if len(violations) != 0 {
		t.Fatalf("violations = %v, want none", violations)
	}
}

// Unviable is absent: a mutant that does not compile cannot be killed by any
// test, so ADR-016 reports it without gating on it.
func TestFindViolationsReportsEveryGatedStatus(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/Countdown.swift":{"mutants":[
		{"mutatorName":"RelationalOperatorReplacement","status":"Killed","location":{"start":{"line":10,"column":5}}},
		{"mutatorName":"RelationalOperatorReplacement","status":"Survived","location":{"start":{"line":11,"column":6}}},
		{"mutatorName":"BooleanLiteralReplacement","status":"Crash","location":{"start":{"line":12,"column":7}}},
		{"mutatorName":"NegateConditional","status":"Timeout","location":{"start":{"line":13,"column":8}}},
		{"mutatorName":"RemoveSideEffects","status":"Unviable","location":{"start":{"line":14,"column":9}}},
		{"mutatorName":"SwapTernary","status":"NoCoverage","location":{"start":{"line":15,"column":10}}}
	]}}}`
	violations, err := findViolations([]byte(report), nil)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
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

func TestFindViolationsSortsByFileThenPosition(t *testing.T) {
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
	violations, err := findViolations([]byte(report), nil)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
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
func TestFindViolationsOrdersSamePositionByReplacement(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","replacement":">=","location":{"start":{"line":3,"column":11}}},
		{"mutatorName":"M","status":"Survived","replacement":"<","location":{"start":{"line":3,"column":11}}}
	]}}}`
	violations, err := findViolations([]byte(report), nil)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
	}
	sortViolations(violations)
	if len(violations) != 2 || violations[0].Replacement != "<" || violations[1].Replacement != ">=" {
		t.Fatalf("violations = %+v, want `<` before `>=`", violations)
	}
}

// findViolations no longer sorts on its own; run sorts once after combining
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

func TestFindViolationsRejectsMalformedJSON(t *testing.T) {
	if _, err := findViolations([]byte("not json"), nil); err == nil {
		t.Fatal("expected an error for malformed JSON")
	}
}

// A report with no files or no mutants means the tool never mutated anything
// (wrong --sources-path, a crashed run), not that every mutant was killed.
func TestFindViolationsRejectsReportWithNoFiles(t *testing.T) {
	if _, err := findViolations([]byte(`{"files":{}}`), nil); err == nil {
		t.Fatal("expected an error for a report with no files")
	}
}

func TestFindViolationsRejectsReportWithNoMutants(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[]}}}`
	if _, err := findViolations([]byte(report), nil); err == nil {
		t.Fatal("expected an error for a report with no mutants")
	}
}

func TestFindViolationsExcludesReviewedEquivalent(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"RelationalOperatorReplacement","status":"Survived","location":{"start":{"line":11,"column":6}}},
		{"mutatorName":"RelationalOperatorReplacement","status":"Survived","location":{"start":{"line":11,"column":7}}}
	]}}}`
	equivalents := []equivalent{{
		File: "Sources/ThrowntomClient/A.swift", Line: 11, Column: 6,
		Mutator: "RelationalOperatorReplacement", Reason: "proven equivalent",
	}}
	violations, err := findViolations([]byte(report), equivalents)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
	}
	if len(violations) != 1 || violations[0].Column != 7 {
		t.Fatalf("violations = %v, want only the column-7 mutant", violations)
	}
}

func TestFindViolationsEquivalentMustMatchMutator(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"NegateConditional","status":"Survived","location":{"start":{"line":11,"column":6}}}
	]}}}`
	equivalents := []equivalent{{
		File: "Sources/ThrowntomClient/A.swift", Line: 11, Column: 6,
		Mutator: "RelationalOperatorReplacement", Reason: "proven equivalent",
	}}
	violations, err := findViolations([]byte(report), equivalents)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
	}
	if len(violations) != 1 {
		t.Fatalf("violations = %v, want the differently-mutated survivor kept", violations)
	}
}

// The tool keys files by the absolute path with the package root sliced off,
// which leaves a leading "/"; equivalents and output use the package-relative
// spelling a reader would type.
func TestFindViolationsStripsLeadingSlashFromReportedFile(t *testing.T) {
	report := `{"files":{"/Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","replacement":">=","location":{"start":{"line":3,"column":11}}},
		{"mutatorName":"M","status":"Survived","replacement":"<","location":{"start":{"line":3,"column":11}}}
	]}}}`
	equivalents := []equivalent{{
		File: "Sources/ThrowntomClient/A.swift", Line: 3, Column: 11,
		Mutator: "M", Replacement: ">=", Reason: "proven equivalent",
	}}
	violations, err := findViolations([]byte(report), equivalents)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
	}
	if len(violations) != 1 || violations[0].String() != "Sources/ThrowntomClient/A.swift:3:11 M Survived" {
		t.Fatalf("violations = %v, want only the unexcluded mutant, package-relative", violations)
	}
}

// One operator yields several mutants at the same position (`>` becomes both
// `>=` and `<`), so excluding one must not hide its siblings.
func TestFindViolationsEquivalentMustMatchReplacement(t *testing.T) {
	report := `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"RelationalOperatorReplacement","status":"Survived","originalText":">","replacement":"<","location":{"start":{"line":3,"column":11}}}
	]}}}`
	equivalents := []equivalent{{
		File: "Sources/ThrowntomClient/A.swift", Line: 3, Column: 11,
		Mutator: "RelationalOperatorReplacement", Replacement: ">=", Reason: "proven equivalent",
	}}
	violations, err := findViolations([]byte(report), equivalents)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
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
	code := run([]string{clean, dirty}, "", &stdout, &stderr)
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
	if code := run([]string{report}, "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1; stderr=%s", code, stderr.String())
	}
	if strings.Contains(stdout.String(), "a`b\nc") {
		t.Fatalf("stdout embeds raw mutant text unescaped:\n%s", stdout.String())
	}
	if !strings.Contains(stdout.String(), "<code>a`b\\nc</code> → <code>&lt;x&gt;</code>") {
		t.Fatalf("stdout missing escaped mutant text:\n%s", stdout.String())
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
	if code := run([]string{first, second}, "", &stdout, &stderr); code != 0 {
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
	if code := run([]string{report}, "", &stdout, &stderr); code != 1 {
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
	if code := run([]string{clean}, "", &stdout, &stderr); code != 0 {
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
	if code := run([]string{clean, missing}, "", &stdout, &stderr); code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
}

func TestRunUnreadableEquivalentsIsAnError(t *testing.T) {
	clean := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":1,"column":1}}}
	]}}}`)
	missing := filepath.Join(t.TempDir(), "absent-equivalents.json")
	var stdout, stderr bytes.Buffer
	if code := run([]string{clean}, missing, &stdout, &stderr); code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
}
