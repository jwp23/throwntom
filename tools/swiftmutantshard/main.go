// Command swiftmutantshard splits a Swift target's source files into shards
// for the weekly mutation run (ADR-016). swift-mutation-testing has no shard
// flag, only --exclude, so for one shard this prints the exclude patterns for
// every file the other shards own, one per line. Files are balanced across
// shards by line count, a proxy for mutant count. The -scope flag also
// excludes the pass-through files sonar.coverage.exclusions names (ADR-018).
package main

import (
	"bufio"
	"bytes"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type sourceFile struct {
	Path  string
	Lines int
}

const (
	exitOK    = 0
	exitError = 2
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("swiftmutantshard", flag.ContinueOnError)
	flags.SetOutput(stderr)
	sources := flags.String("sources", "", "target source directory, e.g. macos/Throwntom/Sources/ThrowntomUI")
	shards := flags.Int("shards", 0, "number of shards")
	index := flags.Int("index", 0, "1-based shard to print excludes for")
	scope := flags.String("scope", "", "sonar-project.properties whose sonar.coverage.exclusions names the pass-through files left out of mutation scope (ADR-018)")
	if err := flags.Parse(args); err != nil {
		return exitError
	}
	var outOfScope map[string]bool
	if *scope != "" {
		var err error
		outOfScope, err = scopeExcludes(*scope, *sources)
		if err != nil {
			_, _ = fmt.Fprintln(stderr, err)
			return exitError
		}
	}
	patterns, err := excludes(*sources, *shards, *index, outOfScope)
	if err != nil {
		_, _ = fmt.Fprintln(stderr, err)
		return exitError
	}
	for _, p := range patterns {
		_, _ = fmt.Fprintln(stdout, p)
	}
	return exitOK
}

// excludes returns the patterns that leave only shard index of shards in
// scope. The tool matches --exclude as a plain substring of each file's
// absolute path, so a pattern is the path from the target directory on, with
// a leading slash: "/ThrowntomUI/Mascot/Arm.swift" cannot match LeftArm.swift.
func excludes(sources string, shards, index int, outOfScope map[string]bool) ([]string, error) {
	if shards < 1 || index < 1 || index > shards {
		return nil, fmt.Errorf("shard %d of %d is out of range", index, shards)
	}
	files, err := discover(sources)
	if err != nil {
		return nil, err
	}
	var inScope []sourceFile
	for _, f := range files {
		if !outOfScope[f.Path] {
			inScope = append(inScope, f)
		}
	}
	if shards > len(inScope) {
		return nil, fmt.Errorf("%d shards for %d files would leave a shard empty", shards, len(inScope))
	}
	target := filepath.Base(sources)
	var patterns []string
	for i, shard := range assign(inScope, shards) {
		if i == index-1 {
			continue
		}
		for _, path := range shard {
			patterns = append(patterns, "/"+target+"/"+path)
		}
	}
	for p := range outOfScope {
		patterns = append(patterns, "/"+target+"/"+p)
	}
	sort.Strings(patterns)
	return patterns, nil
}

// scopeExcludes returns the pass-through files sonar.coverage.exclusions
// names under sources, as slash-separated paths relative to it. ADR-018 makes
// that list the mutation scope too: a file a test process cannot cover holds
// no mutant a test can kill. Every listed Swift file must exist, so a stale
// entry fails the run instead of silently excluding nothing.
func scopeExcludes(propertiesPath, sources string) (map[string]bool, error) {
	entries, err := coverageExclusions(propertiesPath)
	if err != nil {
		return nil, err
	}
	root := filepath.Dir(propertiesPath)
	absSources, err := filepath.Abs(sources)
	if err != nil {
		return nil, err
	}
	scoped := map[string]bool{}
	for _, entry := range entries {
		if !strings.HasSuffix(entry, ".swift") {
			continue
		}
		full := filepath.Join(root, filepath.FromSlash(entry))
		if _, err := os.Stat(full); err != nil {
			return nil, fmt.Errorf("scope list names %s, which does not exist", entry)
		}
		abs, err := filepath.Abs(full)
		if err != nil {
			return nil, err
		}
		rel, err := filepath.Rel(absSources, abs)
		if err != nil || strings.HasPrefix(rel, "..") {
			continue
		}
		scoped[filepath.ToSlash(rel)] = true
	}
	return scoped, nil
}

// coverageExclusions reads the comma-separated value of
// sonar.coverage.exclusions from a properties file. Comment lines start with
// '#'; the value is one line.
func coverageExclusions(path string) ([]string, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read scope list: %w", err)
	}
	const key = "sonar.coverage.exclusions="
	for _, line := range strings.Split(string(raw), "\n") {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, key) {
			continue
		}
		var entries []string
		for _, entry := range strings.Split(strings.TrimPrefix(line, key), ",") {
			if entry = strings.TrimSpace(entry); entry != "" {
				entries = append(entries, entry)
			}
		}
		return entries, nil
	}
	return nil, fmt.Errorf("scope list %s has no sonar.coverage.exclusions", path)
}

// assign distributes files greedily, heaviest first, each to the lightest
// shard so far. Ties break by path and then by lowest shard, so every job in
// a run computes the same split.
func assign(files []sourceFile, shards int) [][]string {
	ordered := append([]sourceFile(nil), files...)
	sort.Slice(ordered, func(i, j int) bool {
		if ordered[i].Lines != ordered[j].Lines {
			return ordered[i].Lines > ordered[j].Lines
		}
		return ordered[i].Path < ordered[j].Path
	})
	result := make([][]string, shards)
	totals := make([]int, shards)
	for _, f := range ordered {
		lightest := 0
		for s := 1; s < shards; s++ {
			if totals[s] < totals[lightest] {
				lightest = s
			}
		}
		result[lightest] = append(result[lightest], f.Path)
		totals[lightest] += f.Lines
	}
	for _, shard := range result {
		sort.Strings(shard)
	}
	return result
}

// discover lists every .swift file under sources with its line count, as a
// slash-separated path relative to sources.
func discover(sources string) ([]sourceFile, error) {
	var files []sourceFile
	err := filepath.WalkDir(sources, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(path, ".swift") {
			return nil
		}
		lines, err := countLines(path)
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(sources, path)
		if err != nil {
			return err
		}
		files = append(files, sourceFile{Path: filepath.ToSlash(rel), Lines: lines})
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("list sources: %w", err)
	}
	if len(files) == 0 {
		return nil, errors.New("list sources: no .swift files found")
	}
	return files, nil
}

func countLines(path string) (int, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}
	lines := 0
	scanner := bufio.NewScanner(bytes.NewReader(data))
	scanner.Buffer(make([]byte, 0, 64*1024), len(data)+1)
	for scanner.Scan() {
		lines++
	}
	return lines, scanner.Err()
}
