// Command swiftmutantsgate enforces the Swift mutation-testing bar ADR-015
// sets: zero unexcluded non-Killed mutants. swift-mutation-testing exits 0
// whatever it finds, so this reads the JSON reports its --output flag writes
// (one per target) and fails on any mutant whose status isn't Killed —
// Survived, Crash, Timeout, Unviable and NoCoverage are each a gap to triage.
// Its stdout is a Markdown list, so the weekly workflow can paste it straight
// into the tracking issue.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
)

type position struct {
	Line   int `json:"line"`
	Column int `json:"column"`
}

type mutant struct {
	MutatorName  string `json:"mutatorName"`
	OriginalText string `json:"originalText"`
	Replacement  string `json:"replacement"`
	Status       string `json:"status"`
	Location     struct {
		Start position `json:"start"`
	} `json:"location"`
}

type fileReport struct {
	Mutants []mutant `json:"mutants"`
}

type report struct {
	Files map[string]fileReport `json:"files"`
}

type violation struct {
	File         string
	Line         int
	Column       int
	Mutator      string
	Status       string
	OriginalText string
	Replacement  string
}

func (v violation) String() string {
	return fmt.Sprintf("%s:%d:%d %s %s", v.File, v.Line, v.Column, v.Mutator, v.Status)
}

func (v violation) markdown() string {
	line := fmt.Sprintf("- `%s:%d:%d` %s %s", v.File, v.Line, v.Column, v.Mutator, v.Status)
	if v.OriginalText != "" || v.Replacement != "" {
		line += fmt.Sprintf(" (%s → %s)", escapeForMarkdownCode(v.OriginalText), escapeForMarkdownCode(v.Replacement))
	}
	return line
}

// escapeForMarkdownCode renders arbitrary mutant text as an HTML <code>
// element instead of backtick-delimited Markdown: OriginalText and
// Replacement come from the mutation tool's source-derived output and can
// contain backticks or newlines that would otherwise split a mutant across
// lines or corrupt the tracking issue body.
func escapeForMarkdownCode(s string) string {
	s = strings.NewReplacer(
		"&", "&amp;",
		"<", "&lt;",
		">", "&gt;",
		"\n", "\\n",
		"\r", "\\r",
	).Replace(s)
	return "<code>" + s + "</code>"
}

// equivalent names one mutant reviewed and proven equivalent — no test can
// ever distinguish it from correct code, so it is not a coverage gap. The
// tool's --exclude only drops whole files; this covers a single mutant in a
// file whose other mutants are worth keeping.
type equivalent struct {
	File        string `json:"file"`
	Line        int    `json:"line"`
	Column      int    `json:"column"`
	Mutator     string `json:"mutator"`
	Replacement string `json:"replacement"`
	Reason      string `json:"reason"`
}

func main() {
	equivalentsPath := flag.String("equivalents", "", "optional path to a reviewed-equivalents JSON allowlist")
	flag.Usage = func() {
		fmt.Fprintln(os.Stderr, "usage: swiftmutantsgate [-equivalents path] report.json [report.json ...]")
	}
	flag.Parse()
	if flag.NArg() == 0 {
		flag.Usage()
		os.Exit(2)
	}
	os.Exit(run(flag.Args(), *equivalentsPath, os.Stdout, os.Stderr))
}

// Unviable mutants do not compile, so no test can kill them; ADR-016 reports
// them without gating on them.
const (
	statusKilled   = "Killed"
	statusUnviable = "Unviable"
)

// Exit codes: the weekly workflow files survivors but must not treat a broken
// run as a score, so the two failures are distinct.
const (
	exitClean      = 0
	exitViolations = 1
	exitError      = 2
)

func run(reportPaths []string, equivalentsPath string, stdout, stderr io.Writer) int {
	equivalents, err := loadEquivalents(equivalentsPath)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return exitError
	}
	var violations []violation
	unviable := 0
	for _, path := range reportPaths {
		data, err := os.ReadFile(path)
		if err != nil {
			_, _ = fmt.Fprintln(stderr, err)
			return exitError
		}
		found, err := findViolations(data, equivalents)
		if err != nil {
			_, _ = fmt.Fprintf(stderr, "%s: %v\n", path, err)
			return exitError
		}
		violations = append(violations, found...)
		unviable += countUnviable(data)
	}
	sortViolations(violations)
	code := exitClean
	if len(violations) == 0 {
		_, _ = fmt.Fprintln(stdout, "No unexcluded mutants survived.")
	} else {
		code = exitViolations
		_, _ = fmt.Fprintf(stdout, "%d unexcluded mutant(s) not killed:\n\n", len(violations))
		for _, v := range violations {
			_, _ = fmt.Fprintln(stdout, v.markdown())
		}
	}
	if unviable > 0 {
		_, _ = fmt.Fprintf(stdout, "\n%d Unviable mutant(s) not gated (ADR-016): they do not compile, so no test can kill them.\n", unviable)
	}
	return code
}

// countUnviable reads a report findViolations has already validated.
func countUnviable(data []byte) int {
	r, err := parseReport(data)
	if err != nil {
		return 0
	}
	count := 0
	for _, f := range r.Files {
		for _, m := range f.Mutants {
			if m.Status == statusUnviable {
				count++
			}
		}
	}
	return count
}

// findViolations reports every mutant whose status isn't Killed, minus any
// reviewed equivalents, ordered by file then position so a refreshed tracking
// issue diffs cleanly week to week.
func findViolations(data []byte, equivalents []equivalent) ([]violation, error) {
	r, err := parseReport(data)
	if err != nil {
		return nil, err
	}
	var violations []violation
	for reported, f := range r.Files {
		file := strings.TrimPrefix(reported, "/")
		for _, m := range f.Mutants {
			if m.Status == statusKilled || m.Status == statusUnviable || isReviewedEquivalent(file, m, equivalents) {
				continue
			}
			violations = append(violations, violation{
				File:         file,
				Line:         m.Location.Start.Line,
				Column:       m.Location.Start.Column,
				Mutator:      m.MutatorName,
				Status:       m.Status,
				OriginalText: m.OriginalText,
				Replacement:  m.Replacement,
			})
		}
	}
	return violations, nil
}

// sortViolations orders by file then position, then by every remaining
// displayed field, so a refreshed tracking issue diffs cleanly week to week
// regardless of report or shard order and two mutants at the same position
// don't tie.
func sortViolations(violations []violation) {
	sort.Slice(violations, func(i, j int) bool {
		a, b := violations[i], violations[j]
		if a.File != b.File {
			return a.File < b.File
		}
		if a.Line != b.Line {
			return a.Line < b.Line
		}
		if a.Column != b.Column {
			return a.Column < b.Column
		}
		if a.Mutator != b.Mutator {
			return a.Mutator < b.Mutator
		}
		if a.Replacement != b.Replacement {
			return a.Replacement < b.Replacement
		}
		if a.OriginalText != b.OriginalText {
			return a.OriginalText < b.OriginalText
		}
		return a.Status < b.Status
	})
}

func isReviewedEquivalent(file string, m mutant, equivalents []equivalent) bool {
	for _, e := range equivalents {
		if e.File == file && e.Line == m.Location.Start.Line &&
			e.Column == m.Location.Start.Column && e.Mutator == m.MutatorName &&
			e.Replacement == m.Replacement {
			return true
		}
	}
	return false
}

// parseReport rejects a report with no mutants at all: that means the tool
// mutated nothing (wrong --sources-path, a run that died), not a clean score.
func parseReport(data []byte) (report, error) {
	var r report
	if err := json.Unmarshal(data, &r); err != nil {
		return report{}, fmt.Errorf("parse mutation report: %w", err)
	}
	for _, f := range r.Files {
		if len(f.Mutants) > 0 {
			return r, nil
		}
	}
	return report{}, fmt.Errorf("parse mutation report: no mutants in report")
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
	for _, e := range equivalents {
		if strings.TrimSpace(e.Reason) == "" {
			return nil, fmt.Errorf("parse equivalents file: %s:%d:%d %s has an empty reason", e.File, e.Line, e.Column, e.Mutator)
		}
	}
	return equivalents, nil
}
