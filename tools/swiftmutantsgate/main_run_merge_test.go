package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

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
// order-dependent test, and either half may be the wrong one. ADR-015's bar is
// zero unexcluded survivors, so a run that saw the mutant survive fails the
// gate: a kill nobody can reproduce is not a kill. The note says why.
func TestRunGatesAKillAnotherRunDisagreedWith(t *testing.T) {
	killed := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Killed","location":{"start":{"line":3,"column":1}}}
	]}}}`)
	survived := writeReport(t, `{"files":{"Sources/ThrowntomClient/A.swift":{"mutants":[
		{"mutatorName":"M","status":"Survived","location":{"start":{"line":3,"column":1}}}
	]}}}`)
	var stdout, stderr bytes.Buffer
	if code := run([]string{killed, survived}, "", "", &stdout, &stderr); code != 1 {
		t.Fatalf("exit = %d, want 1: a mutant one run survived is not killed; stderr=%s", code, stderr.String())
	}
	if !strings.Contains(stdout.String(), "1 unexcluded mutant(s) not killed") ||
		!strings.Contains(stdout.String(), "- `Sources/ThrowntomClient/A.swift:3:1` M Survived") {
		t.Fatalf("the disagreement did not reach the gated list:\n%s", stdout.String())
	}
	want := "- `Sources/ThrowntomClient/A.swift:3:1` M Survived — reported Killed by one run and Survived by another; the gate keeps the survival"
	if !strings.Contains(stdout.String(), want) {
		t.Fatalf("the gate does not say why it kept the survival:\n%s", stdout.String())
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
