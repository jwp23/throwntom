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

// Unwrap joins hard-wrapped prose into single lines, dropping the comment
// marker a wrapped config-template line carries, so a sentence can be looked
// for without depending on where it happens to wrap.
func Unwrap(text string) string {
	text = strings.ReplaceAll(text, "\n# ", " ")
	text = strings.ReplaceAll(text, "\n", " ")
	return strings.Join(strings.Fields(text), " ")
}
