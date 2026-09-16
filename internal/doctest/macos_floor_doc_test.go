package doctest_test

import (
	"regexp"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/doctest"
)

// Where the macOS app's minimum supported OS is stated. The README is what a
// reader believes, Info.plist is what macOS enforces when they double-click,
// and Package.swift is what the compiler builds against. Three statements of
// one fact, in three languages, none of which can see the others: raising the
// floor in the one that failed to build and leaving the other two behind ships
// a bundle that either refuses to launch on an OS the README promised or
// launches on one the code was never compiled for.
var macOSFloorSources = []struct {
	source  string
	pattern *regexp.Regexp
}{
	{"macos/README.md", regexp.MustCompile(`macOS (\d+) or later to run it`)},
	{"macos/bundle/Info.plist", regexp.MustCompile(`<key>LSMinimumSystemVersion</key><string>(\d+)\.0</string>`)},
	{"macos/Throwntom/Package.swift", regexp.MustCompile(`platforms: \[\.macOS\(\.v(\d+)\)\]`)},
}

func TestTheMacOSAppStatesOneMinimumOSEverywhere(t *testing.T) {
	first := ""
	for _, s := range macOSFloorSources {
		text, err := doctest.Read(s.source)
		if err != nil {
			t.Fatalf("read %s: %v", s.source, err)
		}
		match := s.pattern.FindStringSubmatch(doctest.Unwrap(text))
		if match == nil {
			t.Fatalf("%s no longer states a minimum macOS version in the form %q", s.source, s.pattern)
		}
		if first == "" {
			first = match[1]
			continue
		}
		if match[1] != first {
			t.Errorf(
				"%s says the app needs macOS %s; %s says %s",
				s.source, match[1], macOSFloorSources[0].source, first,
			)
		}
	}
}
