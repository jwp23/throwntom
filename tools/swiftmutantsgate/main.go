// Command swiftmutantsgate enforces the Swift mutation-testing bar ADR-015
// sets, as amended by ADR-016: zero unexcluded Survived, Crash, Timeout and
// NoCoverage mutants. swift-mutation-testing exits 0 whatever it finds, so
// this reads the JSON reports its --output flag writes (one per target or
// shard) and fails on any of those. Unviable mutants do not compile, so no
// test can kill them; they are counted but not gated. Its stdout is a
// Markdown list, so the weekly workflow can paste it straight into the
// tracking issue.
//
// Reports are merged by mutant identity rather than concatenated: shards are
// disjoint, but a triage pass runs the tool over one file more than one way on
// purpose, and the two runs can disagree about a mutant. Verdicts that survive
// the merge unsettled are printed whatever the exit code. See merge.go and
// docs/decisions/swift-mutation-timeout-poisons-a-later-mutant.md.
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

// equivalent names one mutant reviewed and excluded: either proven equivalent
// (no test can ever distinguish it from correct code) or a hand-verified real
// kill the tool structurally cannot observe (a Timeout or Crash the harness
// can never report as Killed — see
// docs/decisions/swift-mutation-timeout-poisons-a-later-mutant.md). Either
// way it is not a coverage gap. The tool's --exclude only drops whole files;
// this covers a single mutant in a file whose other mutants are worth keeping.
type equivalent struct {
	File        string `json:"file"`
	Line        int    `json:"line"`
	Column      int    `json:"column"`
	Mutator     string `json:"mutator"`
	Replacement string `json:"replacement"`
	Reason      string `json:"reason"`
}

func (e equivalent) identity() mutantIdentity {
	return mutantIdentity{
		File:        e.File,
		Line:        e.Line,
		Column:      e.Column,
		Mutator:     e.Mutator,
		Replacement: e.Replacement,
	}
}

func main() {
	equivalentsPath := flag.String("equivalents", "", "optional path to a reviewed-equivalents JSON allowlist")
	summaryPath := flag.String("summary", "", "optional path to write a per-file Markdown summary to")
	flag.Usage = func() {
		fmt.Fprintln(os.Stderr, "usage: swiftmutantsgate [-equivalents path] [-summary path] report.json [report.json ...]")
	}
	flag.Parse()
	if flag.NArg() == 0 {
		flag.Usage()
		os.Exit(2)
	}
	os.Exit(run(flag.Args(), *equivalentsPath, *summaryPath, os.Stdout, os.Stderr))
}

// Exit codes: the weekly workflow files survivors but must not treat a broken
// run as a score, so the two failures are distinct.
const (
	exitClean      = 0
	exitViolations = 1
	exitError      = 2
)

// unviableNote is the count ADR-016 reports without gating on it.
func unviableNote(unviable int) string {
	return fmt.Sprintf("%d Unviable mutant(s) not gated (ADR-016): they do not compile, so no test can kill them.\n", unviable)
}

// unsettledNote lists the verdicts the reports do not settle between them, and
// says what to do about each shape. It prints whatever the exit code, because
// both shapes can leave an unkilled mutant behind a verdict the gate lets
// through: a poisoned Unviable and a kill one run disagreed with are both
// ungated.
func unsettledNote(mutants []unsettled) string {
	var b strings.Builder
	_, _ = fmt.Fprintf(&b, "%d verdict(s) the reports do not settle:\n\n", len(mutants))
	for _, m := range mutants {
		_, _ = fmt.Fprintf(&b, "%s — %s\n", m.mutant.markdown(), m.reason)
	}
	b.WriteString(
		"\nswift-mutation-testing SIGKILLs whichever test run is in flight five seconds after another mutant\n" +
			"times out, and reports the run it killed as Crash or as Unviable; re-run those mutants in a scope\n" +
			"with no Timeout and pass both reports. One Timeout spoils at most one run, but no report records\n" +
			"which, so every unconfirmed verdict from such a run is listed. A kill another run disagreed with is\n" +
			"a different problem — no run can invent a Survived — so the gate keeps the survival and fails on it;\n" +
			"settle that one by hand, on whether the killing test can reach the mutant. See\n" +
			"docs/decisions/swift-mutation-timeout-poisons-a-later-mutant.md.\n")
	return b.String()
}

type fileTally struct {
	file     string
	gated    int
	statuses map[string]int
}

// summarize renders the tracking issue body: one row per file with its gated
// count and statuses, heaviest file first. GitHub caps an issue body at 65,536
// characters; a per-mutant list outgrows that, a row per file does not.
func summarize(violations []violation, unviable int) string {
	var b strings.Builder
	if len(violations) == 0 {
		b.WriteString("No unexcluded mutants survived.\n")
	} else {
		tallies := tallyByFile(violations)
		_, _ = fmt.Fprintf(&b, "%d unexcluded mutant(s) not killed in %d file(s).\n\n", len(violations), len(tallies))
		b.WriteString("| File | Gated | Statuses |\n|---|---|---|\n")
		for _, t := range tallies {
			_, _ = fmt.Fprintf(&b, "| `%s` | %d | %s |\n", t.file, t.gated, formatStatuses(t.statuses))
		}
	}
	if unviable > 0 {
		b.WriteString("\n" + unviableNote(unviable))
	}
	return b.String()
}

// tallyByFile counts gated mutants per file, ordered by count and then path so
// identical results render an identical issue body.
func tallyByFile(violations []violation) []fileTally {
	byFile := map[string]*fileTally{}
	for _, v := range violations {
		t := byFile[v.File]
		if t == nil {
			t = &fileTally{file: v.File, statuses: map[string]int{}}
			byFile[v.File] = t
		}
		t.gated++
		t.statuses[v.Status]++
	}
	tallies := make([]fileTally, 0, len(byFile))
	for _, t := range byFile {
		tallies = append(tallies, *t)
	}
	sort.Slice(tallies, func(i, j int) bool {
		if tallies[i].gated != tallies[j].gated {
			return tallies[i].gated > tallies[j].gated
		}
		return tallies[i].file < tallies[j].file
	})
	return tallies
}

func formatStatuses(statuses map[string]int) string {
	names := make([]string, 0, len(statuses))
	for name := range statuses {
		names = append(names, name)
	}
	sort.Strings(names)
	parts := make([]string, 0, len(names))
	for _, name := range names {
		parts = append(parts, fmt.Sprintf("%s %d", name, statuses[name]))
	}
	return strings.Join(parts, ", ")
}

func run(reportPaths []string, equivalentsPath, summaryPath string, stdout, stderr io.Writer) int {
	equivalents, err := loadEquivalents(equivalentsPath)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return exitError
	}
	merged := mutantSet{}
	for _, path := range reportPaths {
		data, err := os.ReadFile(path)
		if err != nil {
			_, _ = fmt.Fprintln(stderr, err)
			return exitError
		}
		if err := merged.add(data); err != nil {
			_, _ = fmt.Fprintf(stderr, "%s: %v\n", path, err)
			return exitError
		}
	}
	violations := findViolations(merged, equivalents)
	unviable := merged.unviable()
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
	if unsettled := merged.unsettledVerdicts(equivalents); len(unsettled) > 0 {
		_, _ = fmt.Fprint(stdout, "\n"+unsettledNote(unsettled))
	}
	if unviable > 0 {
		_, _ = fmt.Fprint(stdout, "\n"+unviableNote(unviable))
	}
	if summaryPath != "" {
		if err := os.WriteFile(summaryPath, []byte(summarize(violations, unviable)), 0o600); err != nil {
			_, _ = fmt.Fprintln(stderr, err)
			return exitError
		}
	}
	return code
}

func sortViolations(violations []violation) {
	sort.Slice(violations, func(i, j int) bool { return violationBefore(violations[i], violations[j]) })
}

// violationBefore orders by file then position, then by every remaining
// displayed field, so a refreshed tracking issue diffs cleanly week to week
// regardless of report or shard order and two mutants at the same position
// don't tie.
func violationBefore(a, b violation) bool {
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
