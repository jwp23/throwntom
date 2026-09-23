// Deciding which of a run's mutants the gate fails on.
//
// The gate reads one report per target or shard, and those scopes are disjoint,
// so the reports are concatenated: every mutant every report names is judged on
// the verdict that report gave it. Nothing reconciles two verdicts for one
// mutant, because nothing produces two. See
// docs/decisions/swift-mutation-timeout-poisons-a-later-mutant.md for the
// defect that once made a report's verdicts untrustworthy in each other's
// company, and ADR-017 for the fork that fixed it.
package main

import "strings"

// The statuses swift-mutation-testing reports. Killed and Unviable are the two
// the gate lets through: a mutant that does not compile cannot be killed by any
// test, so ADR-016 counts it without gating on it.
const (
	statusKilled     = "Killed"
	statusSurvived   = "Survived"
	statusTimeout    = "Timeout"
	statusNoCoverage = "NoCoverage"
	statusCrash      = "Crash"
	statusUnviable   = "Unviable"
)

// mutantIdentity names one mutant the way the reviewed-equivalents allowlist
// does.
type mutantIdentity struct {
	File        string
	Line        int
	Column      int
	Mutator     string
	Replacement string
}

// reportedMutant is one mutant as a report gave it.
type reportedMutant struct {
	identity     mutantIdentity
	status       string
	originalText string
}

// mutantsIn flattens one report into the gate's own shape, spelling each file
// the way the allowlist and the output spell it.
func mutantsIn(data []byte) ([]reportedMutant, error) {
	r, err := parseReport(data)
	if err != nil {
		return nil, err
	}
	var mutants []reportedMutant
	for reported, f := range r.Files {
		file := strings.TrimPrefix(reported, "/")
		for _, m := range f.Mutants {
			mutants = append(mutants, reportedMutant{
				identity: mutantIdentity{
					File:        file,
					Line:        m.Location.Start.Line,
					Column:      m.Location.Start.Column,
					Mutator:     m.MutatorName,
					Replacement: m.Replacement,
				},
				status:       m.Status,
				originalText: m.OriginalText,
			})
		}
	}
	return mutants, nil
}

// violation renders one mutant the way the gate lists it.
func (m reportedMutant) violation() violation {
	return violation{
		File:         m.identity.File,
		Line:         m.identity.Line,
		Column:       m.identity.Column,
		Mutator:      m.identity.Mutator,
		Status:       m.status,
		OriginalText: m.originalText,
		Replacement:  m.identity.Replacement,
	}
}

// findViolations reports every gated mutant, minus any reviewed equivalents, in
// no particular order: run sorts once at the end.
func findViolations(mutants []reportedMutant, equivalents []equivalent) []violation {
	var violations []violation
	for _, m := range mutants {
		if m.status == statusKilled || m.status == statusUnviable || isReviewedEquivalent(m.identity, equivalents) {
			continue
		}
		violations = append(violations, m.violation())
	}
	return violations
}

// countUnviable counts the mutants the gate lets through because they do not
// compile.
func countUnviable(mutants []reportedMutant) int {
	count := 0
	for _, m := range mutants {
		if m.status == statusUnviable {
			count++
		}
	}
	return count
}

func isReviewedEquivalent(id mutantIdentity, equivalents []equivalent) bool {
	for _, e := range equivalents {
		if e.identity() == id {
			return true
		}
	}
	return false
}
