// Merging the reports of more than one run into one verdict per mutant.
//
// Shards are disjoint, so for the weekly workflow this is a pass-through. A
// triage pass is the case it exists for: it runs the tool over one file more
// than one way on purpose, because a run that times a mutant out cannot be
// trusted about every mutant in it, and the two runs then disagree. See
// docs/decisions/swift-mutation-timeout-poisons-a-later-mutant.md.
package main

import (
	"sort"
	"strings"
)

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
// does. Two runs that scope the tool differently report the same mutant under
// the same identity — provided both read the same tree, since an edit above a
// mutant moves its line and leaves the merge matching nothing.
type mutantIdentity struct {
	File        string
	Line        int
	Column      int
	Mutator     string
	Replacement string
}

// observation is everything the reports said about one mutant.
type observation struct {
	identity     mutantIdentity
	OriginalText string
	// statuses maps each verdict this mutant was given to whether some report
	// that gave it timed no mutant out. A verdict only a timeout-bearing report
	// gave may be the harness's doing rather than the mutant's.
	statuses map[string]bool
}

// mutantSet holds every verdict each mutant was given, across every report.
type mutantSet map[mutantIdentity]observation

// statusRank orders verdicts by how much of a test run the tool actually saw,
// most first; the verdict the gate acts on is the best-ranked one any report
// gave. Two runs of one mutant disagree when one of them was disturbed, and a
// disturbed run saw less: the tool SIGKILLs whichever run is in flight five
// seconds after another mutant times out, which reports a killed mutant as
// Crash, or as Unviable if the kill landed before its first test marker.
//
// Survived outranks Killed, which is the one place this is not about how much a
// run saw. Both verdicts come from a run that finished, so neither is the
// disturbed one — a SIGKILLed run exits non-zero and Survived needs an exit code
// of zero, so no run can invent a Survived. That makes the disagreement a flaky
// or order-dependent test, with no way to tell which half was right, and
// ADR-015's bar is zero unexcluded survivors: a kill nobody can reproduce is not
// a kill. The gate keeps the survival, fails, and says why (see unsettled).
//
// Unviable ranks below even an unrecognised status. It is the remaining verdict
// the gate lets through, so letting it win a merge would let a mutant out of the
// gate on the strength of the least informative run there was.
func statusRank(status string) int {
	switch status {
	case statusSurvived:
		return 0
	case statusKilled:
		return 1
	case statusTimeout:
		return 2
	case statusNoCoverage:
		return 3
	case statusCrash:
		return 4
	case statusUnviable:
		return 6
	default:
		return 5
	}
}

// add merges one report into the set.
func (s mutantSet) add(data []byte) error {
	r, err := parseReport(data)
	if err != nil {
		return err
	}
	timeoutFree := !timedOutAMutant(r)
	for reported, f := range r.Files {
		file := strings.TrimPrefix(reported, "/")
		for _, m := range f.Mutants {
			s.record(mutantIdentity{
				File:        file,
				Line:        m.Location.Start.Line,
				Column:      m.Location.Start.Column,
				Mutator:     m.MutatorName,
				Replacement: m.Replacement,
			}, m.Status, m.OriginalText, timeoutFree)
		}
	}
	return nil
}

// record files one report's verdict for one mutant. Every verdict is kept, not
// only the best one: which runs disagreed, and whether any of them timed a
// mutant out, is what tells the gate the verdicts it cannot settle alone.
func (s mutantSet) record(id mutantIdentity, status, originalText string, timeoutFree bool) {
	o, seen := s[id]
	if !seen {
		o = observation{identity: id, statuses: map[string]bool{}}
	}
	if o.OriginalText == "" {
		o.OriginalText = originalText
	}
	o.statuses[status] = o.statuses[status] || timeoutFree
	s[id] = o
}

// timedOutAMutant reports whether a run killed any mutant on its own timeout,
// which is what puts the rest of that run's verdicts in doubt.
func timedOutAMutant(r report) bool {
	for _, f := range r.Files {
		for _, m := range f.Mutants {
			if m.Status == statusTimeout {
				return true
			}
		}
	}
	return false
}

// verdict is the status the gate acts on: the best-ranked one any report gave,
// by name where two rank alike so that one report order cannot print something
// another would not.
func (o observation) verdict() string {
	best := ""
	for status := range o.statuses {
		switch {
		case best == "", statusRank(status) < statusRank(best):
			best = status
		case statusRank(status) == statusRank(best) && status < best:
			best = status
		}
	}
	return best
}

// unsettled says why this mutant's verdict cannot be taken at face value, or ""
// when it can. Two shapes, and they are not the same problem.
//
// A Crash or Unviable no timeout-free run confirms may be the harness's: the
// tool SIGKILLs whichever run is in flight five seconds after another mutant
// times out. Re-running the mutant in a scope with no Timeout settles it.
//
// A mutant one run killed and another survived is *not* that defect — a
// SIGKILLed run exits non-zero and Survived needs an exit code of zero, so no
// run can invent a Survived — which leaves a flaky or order-dependent test, and
// nothing about the two reports says which run was right. The gate keeps the
// survival and fails on it (see statusRank); this is what tells a reader the
// difference between that and a mutant no test ever killed.
func (o observation) unsettled() string {
	if o.statuses[statusKilled] && o.statuses[statusSurvived] {
		return "reported Killed by one run and Survived by another; the gate keeps the survival"
	}
	verdict := o.verdict()
	if verdict != statusCrash && verdict != statusUnviable {
		return ""
	}
	if o.statuses[verdict] {
		return ""
	}
	return "reported " + verdict + " only by a run that also timed a mutant out"
}

// violation renders one mutant the way the gate lists it.
func (o observation) violation() violation {
	return violation{
		File:         o.identity.File,
		Line:         o.identity.Line,
		Column:       o.identity.Column,
		Mutator:      o.identity.Mutator,
		Status:       o.verdict(),
		OriginalText: o.OriginalText,
		Replacement:  o.identity.Replacement,
	}
}

// findViolations reports every gated mutant in the merged set, minus any
// reviewed equivalents, in no particular order: run sorts once at the end.
func findViolations(merged mutantSet, equivalents []equivalent) []violation {
	var violations []violation
	for id, o := range merged {
		verdict := o.verdict()
		if verdict == statusKilled || verdict == statusUnviable || isReviewedEquivalent(id, equivalents) {
			continue
		}
		violations = append(violations, o.violation())
	}
	return violations
}

// unsettledVerdicts lists the mutants no set of reports settles, in the order
// the violations print, minus any reviewed equivalents: an entry there rests on
// a written reason, not on a verdict.
func (s mutantSet) unsettledVerdicts(equivalents []equivalent) []unsettled {
	var found []unsettled
	for id, o := range s {
		reason := o.unsettled()
		if reason == "" || isReviewedEquivalent(id, equivalents) {
			continue
		}
		found = append(found, unsettled{mutant: o.violation(), reason: reason})
	}
	sort.Slice(found, func(i, j int) bool { return violationBefore(found[i].mutant, found[j].mutant) })
	return found
}

// unsettled is one mutant the reports do not settle between them.
type unsettled struct {
	mutant violation
	reason string
}

// unviable counts the mutants the gate lets through because they do not
// compile, once each however many reports carry them.
func (s mutantSet) unviable() int {
	count := 0
	for _, o := range s {
		if o.verdict() == statusUnviable {
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
