package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// violationsIn gates a single report. Combining the disjoint reports of a
// sharded run is exercised through run.
func violationsIn(data []byte, equivalents []equivalent) ([]violation, error) {
	mutants, err := mutantsIn(data)
	if err != nil {
		return nil, err
	}
	return findViolations(mutants, equivalents), nil
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
