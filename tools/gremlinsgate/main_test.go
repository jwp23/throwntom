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
	violations, err := findViolations([]byte(report))
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
	violations, err := findViolations([]byte(report))
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
	if _, err := findViolations([]byte("not json")); err == nil {
		t.Fatal("expected an error for malformed JSON")
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
	code := run(path, &stdout, &stderr)
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
	code := run(path, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit code = %d, want 0; stderr=%s", code, stderr.String())
	}
}

func TestRunReportsErrorForMissingFile(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run("/does/not/exist.json", &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1", code)
	}
	if stderr.Len() == 0 {
		t.Fatal("expected an error message on stderr")
	}
}
