package doctest_test

import (
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/doctest"
)

// swiftLintSelfHeal is what macos/swift-lint.sh does when the binary on PATH
// is not the pinned version: it fetches the pinned release, checks it against
// the checksum, and caches it. The strings are the script's own, so a rewrite
// that drops the mechanism fails here before the prose is even read.
var swiftLintSelfHeal = []string{
	"CACHE_DIR=",
	"download_tool()",
	"SWIFTFORMAT_SHA256=",
	"SWIFTLINT_SHA256=",
}

// The two documents a reader consults before running the Swift linter both
// describe how it gets its tools, and a reader who believes the wrong one
// installs by hand or gives up. A merge that resolves macos/README.md by
// taking a branch's older side reverts the description without touching the
// script, so the agreement is asserted rather than left to review.
func TestDocsSaySwiftLintFetchesItsOwnPinnedTools(t *testing.T) {
	script, err := doctest.Read("macos/swift-lint.sh")
	if err != nil {
		t.Fatalf("read swift-lint.sh: %v", err)
	}
	for _, want := range swiftLintSelfHeal {
		if !strings.Contains(script, want) {
			t.Fatalf("swift-lint.sh no longer fetches and caches its own tools: %q is gone", want)
		}
	}

	for _, d := range []struct {
		source string
		want   string
	}{
		{"macos/README.md", "when the installed version doesn't match, `swift-lint.sh` downloads the pinned release itself"},
		{"macos/README.md", "caches it under `macos/.swift-lint-cache`"},
		{"CLAUDE.md", "the script downloads and checksum-verifies the pinned release itself"},
	} {
		text, err := doctest.Read(d.source)
		if err != nil {
			t.Fatalf("read %s: %v", d.source, err)
		}
		if !strings.Contains(doctest.Unwrap(text), d.want) {
			t.Errorf("%s does not say the script fetches its own pinned tools; it is missing %q", d.source, d.want)
		}
	}
}

// The sentence the mechanism replaced. It is asserted absent because it is
// not merely stale but the opposite of what the script does: a reader told
// the run is refused stops rather than letting it fetch the pin.
func TestDocsDoNotSaySwiftLintRefusesAnUnpinnedTool(t *testing.T) {
	readme, err := doctest.Read("macos/README.md")
	if err != nil {
		t.Fatalf("read macos/README.md: %v", err)
	}
	if strings.Contains(doctest.Unwrap(readme), "the script refuses to run under any other tool version") {
		t.Error("macos/README.md still says swift-lint.sh refuses an unpinned tool; it fetches the pinned one")
	}
}
