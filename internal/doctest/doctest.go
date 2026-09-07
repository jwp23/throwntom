// Package doctest reads the project's prose documentation so a test can pin a
// documented claim about runtime behaviour against the behaviour itself.
//
// internal/config already treats the config template as a test fixture and
// checks the values it states against the real defaults. Every value held;
// the claims that drifted were the sentences around them, which described a
// mechanism and nothing executed to check. These live in files a package test
// has no other way to reach, so reading them is the first step to pinning
// them.
package doctest

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Read returns the text of a documentation file named relative to the
// repository root, so a test asserts against the prose a reader actually sees
// rather than a paraphrase of it. The name is slash-separated.
func Read(name string) (string, error) {
	root, err := repoRoot()
	if err != nil {
		return "", err
	}
	raw, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(name)))
	if err != nil {
		return "", fmt.Errorf("read documentation %q: %w", name, err)
	}
	return string(raw), nil
}

// repoRoot names the directory holding go.mod. Each test runs in its own
// package's directory, so how far the root is varies by caller.
func repoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("working directory: %w", err)
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", errors.New("no go.mod in any parent of the working directory")
		}
		dir = parent
	}
}

// Unwrap joins hard-wrapped prose into a single line, so a sentence can be
// looked for without depending on where it happens to wrap.
func Unwrap(text string) string {
	return strings.Join(strings.Fields(text), " ")
}

// ReadUnwrapped reads a documentation file and unwraps its prose in one step,
// failing the test on a read error. It is what every doc test reaching for
// the README wants: the read and the unwrap are never used apart.
func ReadUnwrapped(t *testing.T, name string) string {
	t.Helper()
	text, err := Read(name)
	if err != nil {
		t.Fatalf("read %s: %v", name, err)
	}
	return Unwrap(text)
}

// UnwrapComments is Unwrap for a file whose prose is a run of comment lines,
// dropping the marker each wrapped line carries. Markdown keeps its own
// meaning for "# ", so a document that is not commented out uses Unwrap.
func UnwrapComments(text string) string {
	return Unwrap(strings.ReplaceAll(text, "\n# ", " "))
}
