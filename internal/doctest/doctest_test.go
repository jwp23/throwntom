package doctest

import (
	"strings"
	"testing"
)

func TestReadFindsADocumentFromAnyPackageDirectory(t *testing.T) {
	// The working directory is this package's, two levels below the root, so
	// a name that resolves at all proves the walk up to go.mod.
	text, err := Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	if !strings.Contains(text, "# throwntom") {
		t.Fatal("the file read does not look like the project README")
	}
}

func TestReadReportsAMissingDocument(t *testing.T) {
	if _, err := Read("no-such-document.md"); err == nil {
		t.Fatal("expected an error for a document that does not exist")
	}
}

func TestUnwrapJoinsWrappedProse(t *testing.T) {
	got := Unwrap("a sentence that\nwraps across\n  three lines")
	if want := "a sentence that wraps across three lines"; got != want {
		t.Fatalf("Unwrap gave %q, want %q", got, want)
	}
}

// A markdown heading keeps its marker: only a commented-out document loses
// one, and Unwrap is what the markdown documents are read with.
func TestUnwrapKeepsAMarkdownHeading(t *testing.T) {
	got := Unwrap("the end of a sentence\n# A Heading")
	if want := "the end of a sentence # A Heading"; got != want {
		t.Fatalf("Unwrap gave %q, want %q", got, want)
	}
}

func TestUnwrapCommentsDropsTheContinuationMarker(t *testing.T) {
	got := UnwrapComments("# a sentence that\n# wraps across\n# three lines")
	if want := "# a sentence that wraps across three lines"; got != want {
		t.Fatalf("UnwrapComments gave %q, want %q", got, want)
	}
}
