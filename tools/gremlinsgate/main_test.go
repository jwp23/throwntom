package main

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

func TestFindViolationsAllKilledIsClean(t *testing.T) {
	report := `{"files":[{"file_name":"internal/x/y.go","mutations":[
		{"type":"CONDITIONALS_BOUNDARY","status":"KILLED","line":10,"column":5}
	]}]}`
	violations, err := findViolations([]byte(report), nil)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
	}
	if len(violations) != 0 {
		t.Fatalf("violations = %v, want none", violations)
	}
}

func TestFindViolationsReportsEveryNonKilledStatus(t *testing.T) {
	report := `{"files":[{"file_name":"internal/x/y.go","mutations":[
		{"type":"CONDITIONALS_BOUNDARY","status":"KILLED","line":10,"column":5},
		{"type":"CONDITIONALS_NEGATION","status":"LIVED","line":11,"column":6},
		{"type":"ARITHMETIC_BASE","status":"NOT COVERED","line":12,"column":7},
		{"type":"CONDITIONALS_NEGATION","status":"TIMED OUT","line":13,"column":8},
		{"type":"INVERT_NEGATIVES","status":"NOT VIABLE","line":14,"column":9}
	]}]}`
	violations, err := findViolations([]byte(report), nil)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
	}
	if len(violations) != 4 {
		t.Fatalf("violations = %v, want 4 (every non-KILLED status)", violations)
	}
	for _, want := range []string{"LIVED", "NOT COVERED", "TIMED OUT", "NOT VIABLE"} {
		found := false
		for _, v := range violations {
			if v.Status == want {
				found = true
			}
		}
		if !found {
			t.Errorf("missing violation for status %q", want)
		}
	}
}

func TestFindViolationsRejectsMalformedJSON(t *testing.T) {
	if _, err := findViolations([]byte("not json"), nil); err == nil {
		t.Fatal("expected an error for malformed JSON")
	}
}

// TestFindViolationsRejectsReportWithNoFiles guards against a truncated or
// empty gremlins report silently passing as "no unexcluded survivors" — an
// absent files list means gremlins never ran the mutation, not that it found
// none.
func TestFindViolationsRejectsReportWithNoFiles(t *testing.T) {
	if _, err := findViolations([]byte(`{"files":[]}`), nil); err == nil {
		t.Fatal("expected an error for a report with no files")
	}
}

// TestFindViolationsRejectsReportWithNoMutations guards the same failure
// mode when files are present but every one of them lists zero mutations —
// still a sign the run produced no real data, not a clean pass.
func TestFindViolationsRejectsReportWithNoMutations(t *testing.T) {
	report := `{"files":[{"file_name":"a.go","mutations":[]},{"file_name":"b.go","mutations":[]}]}`
	if _, err := findViolations([]byte(report), nil); err == nil {
		t.Fatal("expected an error for a report where every file has zero mutations")
	}
}

// TestFindViolationsSkipsReviewedEquivalents covers ADR-014's equivalence
// policy: gremlins only excludes whole files, so a single mutant proven
// mathematically equivalent (no test can ever distinguish it from correct
// code) needs its own reviewed allowlist rather than sacrificing a file's
// real coverage to silence one line.
func TestFindViolationsSkipsReviewedEquivalents(t *testing.T) {
	report := `{"files":[{"file_name":"a.go","mutations":[
		{"type":"CONDITIONALS_BOUNDARY","status":"LIVED","line":10,"column":5},
		{"type":"CONDITIONALS_BOUNDARY","status":"LIVED","line":20,"column":9}
	]}]}`
	equivalents := []equivalent{
		{File: "a.go", Line: 10, Column: 5, Type: "CONDITIONALS_BOUNDARY", Reason: "proven equivalent"},
	}
	violations, err := findViolations([]byte(report), equivalents)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
	}
	if len(violations) != 1 {
		t.Fatalf("violations = %v, want exactly the unreviewed one at line 20", violations)
	}
	if violations[0].Line != 20 {
		t.Fatalf("violations = %v, want the survivor at line 20 kept", violations)
	}
}

// TestFindViolationsEquivalentMustMatchTypeToo guards against an allowlist
// entry silencing every mutant at a line:column regardless of mutator type —
// a reviewed equivalent is equivalent for one specific mutation, not
// whatever gremlins happens to plant there next.
func TestFindViolationsEquivalentMustMatchTypeToo(t *testing.T) {
	report := `{"files":[{"file_name":"a.go","mutations":[
		{"type":"CONDITIONALS_NEGATION","status":"LIVED","line":10,"column":5}
	]}]}`
	equivalents := []equivalent{
		{File: "a.go", Line: 10, Column: 5, Type: "CONDITIONALS_BOUNDARY", Reason: "proven equivalent"},
	}
	violations, err := findViolations([]byte(report), equivalents)
	if err != nil {
		t.Fatalf("findViolations: %v", err)
	}
	if len(violations) != 1 {
		t.Fatalf("violations = %v, want the CONDITIONALS_NEGATION survivor kept (different type than the allowlisted one)", violations)
	}
}

func TestLoadEquivalentsFromFile(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/equivalents.json"
	body := `[{"file":"a.go","line":10,"column":5,"type":"CONDITIONALS_BOUNDARY","reason":"proven equivalent"}]`
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	got, err := loadEquivalents(path)
	if err != nil {
		t.Fatalf("loadEquivalents: %v", err)
	}
	want := []equivalent{{File: "a.go", Line: 10, Column: 5, Type: "CONDITIONALS_BOUNDARY", Reason: "proven equivalent"}}
	if len(got) != 1 || got[0] != want[0] {
		t.Fatalf("loadEquivalents = %v, want %v", got, want)
	}
}

// TestLoadEquivalentsRejectsEmptyReason guards ADR-014's equivalence policy:
// every allowlist entry must carry a reviewed justification, so an empty or
// whitespace-only reason (a stub someone forgot to fill in) fails loudly
// instead of silently exempting a mutant with no review behind it.
func TestLoadEquivalentsRejectsEmptyReason(t *testing.T) {
	dir := t.TempDir()
	path := dir + "/equivalents.json"
	body := `[{"file":"a.go","line":10,"column":5,"type":"CONDITIONALS_BOUNDARY","reason":"   "}]`
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := loadEquivalents(path); err == nil {
		t.Fatal("expected an error for a whitespace-only reason")
	}
}

func TestLoadEquivalentsEmptyPathIsNoEquivalents(t *testing.T) {
	got, err := loadEquivalents("")
	if err != nil {
		t.Fatalf("loadEquivalents(\"\"): %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("loadEquivalents(\"\") = %v, want none", got)
	}
}

func TestRunExitsNonZeroOnAnySurvivor(t *testing.T) {
	report := `{"files":[{"file_name":"a.go","mutations":[{"type":"CONDITIONALS_BOUNDARY","status":"LIVED","line":1,"column":1}]}]}`
	dir := t.TempDir()
	path := dir + "/report.json"
	if err := os.WriteFile(path, []byte(report), 0o600); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	code := run(path, "", &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1", code)
	}
	if !strings.Contains(stdout.String(), "a.go:1:1") {
		t.Fatalf("stdout = %q, want it to name the surviving mutant", stdout.String())
	}
}

func TestRunExitsZeroWhenClean(t *testing.T) {
	report := `{"files":[{"file_name":"a.go","mutations":[{"type":"CONDITIONALS_BOUNDARY","status":"KILLED","line":1,"column":1}]}]}`
	dir := t.TempDir()
	path := dir + "/report.json"
	if err := os.WriteFile(path, []byte(report), 0o600); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	code := run(path, "", &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit code = %d, want 0; stderr=%s", code, stderr.String())
	}
}

func TestRunReportsErrorForMissingFile(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run("/does/not/exist.json", "", &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1", code)
	}
	if stderr.Len() == 0 {
		t.Fatal("expected an error message on stderr")
	}
}

func TestRunExitsZeroWhenOnlySurvivorIsAReviewedEquivalent(t *testing.T) {
	report := `{"files":[{"file_name":"a.go","mutations":[{"type":"CONDITIONALS_BOUNDARY","status":"LIVED","line":1,"column":1}]}]}`
	dir := t.TempDir()
	reportPath := dir + "/report.json"
	if err := os.WriteFile(reportPath, []byte(report), 0o600); err != nil {
		t.Fatal(err)
	}
	equivPath := dir + "/equivalents.json"
	equiv := `[{"file":"a.go","line":1,"column":1,"type":"CONDITIONALS_BOUNDARY","reason":"proven equivalent"}]`
	if err := os.WriteFile(equivPath, []byte(equiv), 0o600); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	code := run(reportPath, equivPath, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit code = %d, want 0; stdout=%s stderr=%s", code, stdout.String(), stderr.String())
	}
	if !strings.Contains(stdout.String(), "1 known-equivalent") {
		t.Fatalf("stdout = %q, want it to say the equivalent was excluded, not hidden", stdout.String())
	}
}
