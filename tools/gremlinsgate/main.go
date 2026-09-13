// Command gremlinsgate enforces the mutation-testing bar ADR-014 sets: zero
// unexcluded non-KILLED mutants. gremlins itself only fails a run on
// percentage thresholds; ADR-014 sets none, since NOT COVERED, LIVED, TIMED
// OUT and NOT VIABLE are each a real gap to triage rather than a rate to
// average against, so this reads gremlins' JSON report and fails on any
// mutant whose status isn't KILLED.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
)

type mutation struct {
	Type   string `json:"type"`
	Status string `json:"status"`
	Line   int    `json:"line"`
	Column int    `json:"column"`
}

type fileReport struct {
	FileName  string     `json:"file_name"`
	Mutations []mutation `json:"mutations"`
}

type report struct {
	Files []fileReport `json:"files"`
}

type violation struct {
	File   string
	Type   string
	Status string
	Line   int
	Column int
}

// equivalent names one mutant reviewed and proven equivalent — no test can
// ever distinguish it from correct code, so it is not a coverage gap.
// gremlins only excludes whole files (exclude-files in .gremlins.yaml);
// this allowlist covers the case ADR-014 anticipates but gremlins can't
// express: a single mutant excluded on its own reviewed merits, in a file
// whose other mutants are real, worth-keeping coverage.
type equivalent struct {
	File   string `json:"file"`
	Line   int    `json:"line"`
	Column int    `json:"column"`
	Type   string `json:"type"`
	Reason string `json:"reason"`
}

func main() {
	reportPath := flag.String("report", "", "path to gremlins JSON report (produced by unleash -o)")
	equivalentsPath := flag.String("equivalents", "", "optional path to a reviewed-equivalents JSON allowlist")
	flag.Parse()
	if *reportPath == "" {
		fmt.Fprintln(os.Stderr, "gremlinsgate: -report is required")
		os.Exit(2)
	}
	os.Exit(run(*reportPath, *equivalentsPath, os.Stdout, os.Stderr))
}

func run(reportPath, equivalentsPath string, stdout, stderr io.Writer) int {
	data, err := os.ReadFile(reportPath)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
	}
	equivalents, err := loadEquivalents(equivalentsPath)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
	}
	violations, err := findViolations(data, equivalents)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
	}
	excluded := countExcludedEquivalents(data, equivalents)
	if excluded > 0 {
		_, _ = fmt.Fprintf(stdout, "gremlinsgate: %d known-equivalent mutant(s) excluded (reviewed, see -equivalents)\n", excluded)
	}
	if len(violations) == 0 {
		_, _ = fmt.Fprintln(stdout, "gremlinsgate: no unexcluded survivors")
		return 0
	}
	_, _ = fmt.Fprintf(stdout, "gremlinsgate: %d unexcluded mutant(s) not killed:\n", len(violations))
	for _, v := range violations {
		_, _ = fmt.Fprintf(stdout, "  %s:%d:%d %s %s\n", v.File, v.Line, v.Column, v.Type, v.Status)
	}
	return 1
}

// findViolations reports every mutation whose status isn't KILLED, minus any
// reviewed equivalents. Files gremlins never mutated at all (ADR-014's
// exclude-files scope) don't appear in the report, so they never reach here.
func findViolations(data []byte, equivalents []equivalent) ([]violation, error) {
	r, err := parseReport(data)
	if err != nil {
		return nil, err
	}
	var violations []violation
	for _, f := range r.Files {
		for _, m := range f.Mutations {
			if m.Status == "KILLED" {
				continue
			}
			if isReviewedEquivalent(f.FileName, m, equivalents) {
				continue
			}
			violations = append(violations, violation{
				File:   f.FileName,
				Type:   m.Type,
				Status: m.Status,
				Line:   m.Line,
				Column: m.Column,
			})
		}
	}
	return violations, nil
}

// countExcludedEquivalents reports how many mutants in data an equivalents
// allowlist actually matched, so a stale entry (the mutant it named got
// KILLED by an unrelated test change, or never existed) is silently worth
// zero rather than silently claimed.
func countExcludedEquivalents(data []byte, equivalents []equivalent) int {
	r, err := parseReport(data)
	if err != nil {
		return 0
	}
	count := 0
	for _, f := range r.Files {
		for _, m := range f.Mutations {
			if m.Status != "KILLED" && isReviewedEquivalent(f.FileName, m, equivalents) {
				count++
			}
		}
	}
	return count
}

func isReviewedEquivalent(fileName string, m mutation, equivalents []equivalent) bool {
	for _, e := range equivalents {
		if e.File == fileName && e.Line == m.Line && e.Column == m.Column && e.Type == m.Type {
			return true
		}
	}
	return false
}

func parseReport(data []byte) (report, error) {
	var r report
	if err := json.Unmarshal(data, &r); err != nil {
		return report{}, fmt.Errorf("parse gremlins report: %w", err)
	}
	return r, nil
}

// loadEquivalents reads the reviewed-equivalents allowlist. An empty path
// means no allowlist was configured, not an error.
func loadEquivalents(path string) ([]equivalent, error) {
	if path == "" {
		return nil, nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read equivalents file: %w", err)
	}
	var equivalents []equivalent
	if err := json.Unmarshal(data, &equivalents); err != nil {
		return nil, fmt.Errorf("parse equivalents file: %w", err)
	}
	return equivalents, nil
}
