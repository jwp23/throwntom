package main

import (
	"bytes"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
)

func TestAssignBalancesByLineCount(t *testing.T) {
	files := []sourceFile{
		{Path: "a.swift", Lines: 1},
		{Path: "b.swift", Lines: 9},
		{Path: "c.swift", Lines: 10},
		{Path: "d.swift", Lines: 1},
	}
	// Heaviest first, each to the lighter shard: c(10)→0, b(9)→1, then the
	// 1-line files by path: a→1 (9<10), d→0 (10=10, lowest shard wins).
	got := assign(files, 2)
	want := [][]string{
		{"c.swift", "d.swift"},
		{"a.swift", "b.swift"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("assign = %v, want %v", got, want)
	}
}

// Equal weights must land the same way on every machine, or two jobs of one
// run could each skip the same file.
func TestAssignBreaksTiesByPath(t *testing.T) {
	files := []sourceFile{
		{Path: "z.swift", Lines: 5},
		{Path: "m.swift", Lines: 5},
		{Path: "a.swift", Lines: 5},
	}
	got := assign(files, 2)
	want := [][]string{
		{"a.swift", "z.swift"},
		{"m.swift"},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("assign = %v, want %v", got, want)
	}
}

func TestAssignPlacesEveryFileInExactlyOneShard(t *testing.T) {
	var files []sourceFile
	for i, lines := range []int{40, 3, 17, 17, 8, 250, 1, 66, 9, 12, 30} {
		files = append(files, sourceFile{Path: string(rune('a'+i)) + ".swift", Lines: lines})
	}
	var all []string
	for _, shard := range assign(files, 4) {
		all = append(all, shard...)
	}
	sort.Strings(all)
	var want []string
	for _, f := range files {
		want = append(want, f.Path)
	}
	sort.Strings(want)
	if !reflect.DeepEqual(all, want) {
		t.Fatalf("files across shards = %v, want each of %v exactly once", all, want)
	}
}

func writeSwift(t *testing.T, path string, lines int) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(strings.Repeat("let x = 1\n", lines)), 0o600); err != nil {
		t.Fatal(err)
	}
}

// The tool's --exclude is a plain substring test on the file's absolute path,
// so patterns carry the target directory and a leading slash: a bare
// "Arm.swift" would also exclude "LeftArm.swift".
func TestExcludesAreSlashAnchoredToTheTargetDirectory(t *testing.T) {
	// Weights put Arm (20) in shard 1 and LeftArm (15) with Big (10) in
	// shard 2, so the two look-alike names are split across shards.
	sources := filepath.Join(t.TempDir(), "Sources", "ThrowntomUI")
	writeSwift(t, filepath.Join(sources, "Big.swift"), 10)
	writeSwift(t, filepath.Join(sources, "Mascot", "Arm.swift"), 20)
	writeSwift(t, filepath.Join(sources, "Mascot", "LeftArm.swift"), 15)
	writeSwift(t, filepath.Join(sources, "notes.txt"), 99)

	got, err := excludes(sources, 2, 1)
	if err != nil {
		t.Fatalf("excludes: %v", err)
	}
	want := []string{"/ThrowntomUI/Big.swift", "/ThrowntomUI/Mascot/LeftArm.swift"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("shard 1 of 2 excludes = %v, want %v", got, want)
	}
	got, err = excludes(sources, 2, 2)
	if err != nil {
		t.Fatalf("excludes: %v", err)
	}
	want = []string{"/ThrowntomUI/Mascot/Arm.swift"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("shard 2 of 2 excludes = %v, want %v", got, want)
	}
}

func TestExcludesSingleShardExcludesNothing(t *testing.T) {
	sources := filepath.Join(t.TempDir(), "Sources", "ThrowntomClient")
	writeSwift(t, filepath.Join(sources, "A.swift"), 3)
	got, err := excludes(sources, 1, 1)
	if err != nil {
		t.Fatalf("excludes: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("excludes = %v, want none", got)
	}
}

// A shard with no files would hand the mutation tool an empty scope, which the
// gate rejects as a broken run; refuse up front instead.
func TestExcludesRejectsInvalidShardArguments(t *testing.T) {
	sources := filepath.Join(t.TempDir(), "Sources", "ThrowntomUI")
	writeSwift(t, filepath.Join(sources, "A.swift"), 3)
	writeSwift(t, filepath.Join(sources, "B.swift"), 3)
	for _, tc := range []struct {
		name          string
		shards, index int
	}{
		{"zero shards", 0, 1},
		{"index zero", 2, 0},
		{"index past count", 2, 3},
		{"more shards than files", 3, 1},
	} {
		if _, err := excludes(sources, tc.shards, tc.index); err == nil {
			t.Errorf("%s: expected an error for shards=%d index=%d", tc.name, tc.shards, tc.index)
		}
	}
}

func TestRunPrintsOnePatternPerLine(t *testing.T) {
	sources := filepath.Join(t.TempDir(), "Sources", "ThrowntomUI")
	writeSwift(t, filepath.Join(sources, "A.swift"), 5)
	writeSwift(t, filepath.Join(sources, "B.swift"), 4)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"-sources", sources, "-shards", "2", "-index", "1"}, &stdout, &stderr); code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr.String())
	}
	if stdout.String() != "/ThrowntomUI/B.swift\n" {
		t.Fatalf("stdout = %q, want the other shard's file", stdout.String())
	}
}

func TestRunInvalidArgumentsExitTwo(t *testing.T) {
	var stdout, stderr bytes.Buffer
	if code := run([]string{"-sources", t.TempDir(), "-shards", "0", "-index", "1"}, &stdout, &stderr); code != 2 {
		t.Fatalf("exit = %d, want 2", code)
	}
}
