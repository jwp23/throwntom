package main

import (
	"github.com/charmbracelet/lipgloss"

	"regexp"
	"strconv"
	"strings"
	"testing"

	"github.com/jwp23/throwntom/v3/internal/config"
	"github.com/jwp23/throwntom/v3/internal/doctest"
)

// The README prints a table of tier ranges and the config template describes
// the same thresholds in prose. tierMark compares with a strict >, which is
// exactly the kind of boundary prose gets wrong in both directions, so both
// documents are read here and checked against the function.

// tierRow matches one row of the README's tier table: a name, a range such as
// "0–2" or "6+", and the glyph.
var tierRow = regexp.MustCompile(`\|\s*(\w+)\s*\|\s*(\d+)(?:–(\d+)|\+)\s*\|\s*(\S)\s*\|\s*(\w+)\s*\|`)

// documentedColors maps the colour names the README's table uses to the theme
// colours tierMark actually returns. A glyph alone leaves half of every
// documented row unchecked: swapping two of these in stats_handler.go would
// make the table wrong with nothing to say so.
var documentedColors = map[string]lipgloss.TerminalColor{
	"gray":   colorDim,
	"tomato": colorTomato,
	"teal":   colorTeal,
}

// TestDocumentedTierRangesAreWhatTierMarkDoes reads the README's table and
// checks every count it covers against tierMark at the documented defaults.
func TestDocumentedTierRangesAreWhatTierMarkDoes(t *testing.T) {
	readme, err := doctest.Read("README.md")
	if err != nil {
		t.Fatalf("read README: %v", err)
	}
	rows := tierRow.FindAllStringSubmatch(readme, -1)
	if len(rows) != 3 {
		t.Fatalf("README's tier table has %d readable rows, want the three tiers", len(rows))
	}

	defaults := config.Default().Stats
	// The table is headed "Default range", so it describes the defaults. A
	// table checked against other thresholds would prove nothing about it.
	if defaults.TierLow != 2 || defaults.TierMid != 5 {
		t.Fatalf("the defaults are now %d/%d; the README's table is headed as the default range",
			defaults.TierLow, defaults.TierMid)
	}

	// The open-ended row ("6+") has no upper bound to read, so probe a few
	// counts past its lower one: all of them are still that tier.
	const beyondTheTable = 3
	// The rows must cover every count from 0 with no gap: a table missing a
	// count between two declared ranges would still pass if each row were
	// only checked against its own bounds.
	wantLow := 0
	for i, row := range rows {
		tier, glyph := row[1], row[4]
		low, err := strconv.Atoi(row[2])
		if err != nil {
			t.Fatalf("tier %s: unreadable lower bound %q", tier, row[2])
		}
		if low != wantLow {
			t.Fatalf("tier %s starts at %d; the previous row leaves %d uncovered", tier, low, wantLow)
		}
		open := row[3] == ""
		if open && i != len(rows)-1 {
			t.Fatalf("tier %s has no upper bound but is not the last row", tier)
		}
		high := low + beyondTheTable
		if !open {
			if high, err = strconv.Atoi(row[3]); err != nil {
				t.Fatalf("tier %s: unreadable upper bound %q", tier, row[3])
			}
		}
		wantColor, known := documentedColors[row[5]]
		if !known {
			t.Fatalf("tier %s: README names the colour %q, which this test cannot match to a theme colour", tier, row[5])
		}
		wantLow = high + 1
		for count := low; count <= high; count++ {
			got, style := tierMark(count, defaults.TierLow, defaults.TierMid)
			if got != glyph {
				t.Errorf("README puts %d in %s (%s); tierMark gives %s", count, tier, glyph, got)
			}
			if fg := style.GetForeground(); fg != wantColor {
				t.Errorf("README colours %d %s (%s); tierMark gives %v", count, row[5], tier, fg)
			}
		}
	}
}

// TestTemplateStatesTheStrictTierBoundaries pins the config template's worked
// example, which exists because both boundaries read the other way at a
// glance: with tier_low = 2 and tier_mid = 5 a day of 2 is not moderate and a
// day of 5 is not full.
func TestTemplateStatesTheStrictTierBoundaries(t *testing.T) {
	const claim = "Both are strict, so with the defaults a day of 2 is light and a day of 5 is moderate"
	if !strings.Contains(doctest.UnwrapComments(config.Template), claim) {
		t.Errorf("the config template no longer says %q", claim)
	}

	// Probed at the thresholds themselves rather than at 2 and 5, so a change
	// of defaults reports the boundary that broke instead of blaming the one
	// that did not.
	defaults := config.Default().Stats
	light, _ := tierMark(defaults.TierLow, defaults.TierLow, defaults.TierMid)
	moderate, _ := tierMark(defaults.TierMid, defaults.TierLow, defaults.TierMid)
	full, _ := tierMark(defaults.TierMid+1, defaults.TierLow, defaults.TierMid)

	if light == moderate {
		t.Errorf("a day of %d marks %s, the same as a day of %d: tier_low is no longer strict",
			defaults.TierLow, light, defaults.TierMid)
	}
	if moderate == full {
		t.Errorf("a day of %d marks %s, the same as a day of %d: tier_mid is no longer strict",
			defaults.TierMid, moderate, defaults.TierMid+1)
	}
}
