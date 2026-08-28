---
name: swift-review
description: Use when a branch changes Swift files under macos/ and is about to be called done, committed as finished, pushed, or turned into a PR — the Swift review gate before finishing-a-development-branch.
---

# Swift Review

## Overview

Two checks, neither optional, both scoped to what the branch changed. The linter proves
style; it says nothing about deprecated SwiftUI API, data flow, accessibility, or concurrency,
which is what the swiftui-pro review exists for. Lint passing is not a review.

Swift files this branch touches:
!`git diff --name-only origin/main -- 'macos/Throwntom/*.swift'`

## The gate

1. **Style:** `macos/swift-lint.sh`. Red means fix (`--fix`, then hand-fix the rest); never
   loosen `.swiftformat`/`.swiftlint.yml` and never skip the hook.
2. **Review:** invoke the `swiftui-pro:swiftui-pro` skill over the **diff only** —
   `git diff origin/main -- 'macos/Throwntom/*.swift'` — never the whole package.
   What costs tokens is reading files the branch did not change: a full-package pass reads
   ~4k lines, a typical branch a few hundred. Test files count; they are Swift too.
3. **Findings:** fix in this branch when the change is small and inside the branch's scope;
   otherwise file a bead (`bd create`) under the branch's bead and say so in the report.
   A finding that is neither fixed nor filed is a finding you hid.
4. **Report** (in the hand-off): lint result, the files reviewed, each finding with its
   rule and fixed/filed status, or "swiftui-pro: no findings on N files".

Only after all four: proceed to finishing-a-development-branch.

## Rationalizations that do not excuse the review

| Excuse | Reality |
|---|---|
| "It's only a formatting / lint sweep" | Reformatting rewrites every line; a review of the diff is cheap and the only check that reads it. |
| "Tests are green" | Tests never fail on deprecated API, missing VoiceOver labels, or a `Binding(get:set:)` feedback loop. |
| "swift-lint passed, style is covered" | Style ≠ review. The linter has no SwiftUI rules. |
| "Joe wants it up in five minutes" | The diff-scoped review takes one skill call. Skipping it is what makes the next session's fix list. |
| "The `swift` skill was loaded while writing" | That skill guides writing; nobody has read the result yet. |
| "No SwiftUI in this change, just the client target" | swiftui-pro also covers Swift concurrency, hygiene and modern Foundation API. |

## Red flags — stop, run the gate

- Drafting a PR body and the report has no "swiftui-pro" line
- Calling the branch done from a green test run alone
- Reviewing the whole package "to be thorough" instead of the diff
- Deciding a finding is "out of scope" without filing a bead
