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

func main() {
	path := flag.String("report", "", "path to gremlins JSON report (produced by unleash -o)")
	flag.Parse()
	if *path == "" {
		fmt.Fprintln(os.Stderr, "gremlinsgate: -report is required")
		os.Exit(2)
	}
	os.Exit(run(*path, os.Stdout, os.Stderr))
}

func run(path string, stdout, stderr io.Writer) int {
	data, err := os.ReadFile(path)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
	}
	violations, err := findViolations(data)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return 1
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

// findViolations reports every mutation whose status isn't KILLED. Files
// gremlins never mutated at all (ADR-014's exclude-files scope) don't appear
// in the report, so they never reach here.
func findViolations(data []byte) ([]violation, error) {
	var r report
	if err := json.Unmarshal(data, &r); err != nil {
		return nil, fmt.Errorf("parse gremlins report: %w", err)
	}
	var violations []violation
	for _, f := range r.Files {
		for _, m := range f.Mutations {
			if m.Status == "KILLED" {
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
