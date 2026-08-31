package main

import (
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
var tierRow = regexp.MustCompile(`\|\s*(\w+)\s*\|\s*(\d+)(?:–(\d+)|\+)\s*\|\s*(\S)\s*\|`)

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

	// The open-ended row's upper bound: one past it is still the same tier.
	const beyondTheTable = 3
	for _, row := range rows {
		tier, glyph := row[1], row[4]
		low, err := strconv.Atoi(row[2])
		if err != nil {
			t.Fatalf("tier %s: unreadable lower bound %q", tier, row[2])
		}
		high := low + beyondTheTable
		if row[3] != "" {
			if high, err = strconv.Atoi(row[3]); err != nil {
				t.Fatalf("tier %s: unreadable upper bound %q", tier, row[3])
			}
		}
		for count := low; count <= high; count++ {
			got, _ := tierMark(count, defaults.TierLow, defaults.TierMid)
			if got != glyph {
				t.Errorf("README puts %d in %s (%s); tierMark gives %s", count, tier, glyph, got)
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

	defaults := config.Default().Stats
	light, _ := tierMark(2, defaults.TierLow, defaults.TierMid)
	moderate, _ := tierMark(5, defaults.TierLow, defaults.TierMid)
	full, _ := tierMark(6, defaults.TierLow, defaults.TierMid)

	if light == moderate {
		t.Errorf("a day of 2 marks %s, the same as a day of 5: tier_low is no longer strict", light)
	}
	if moderate == full {
		t.Errorf("a day of 5 marks %s, the same as a day of 6: tier_mid is no longer strict", moderate)
	}
}
