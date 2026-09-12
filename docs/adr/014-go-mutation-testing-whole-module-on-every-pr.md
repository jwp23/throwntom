# ADR-014: Go Mutation Testing Runs Whole-Module on Every PR

This ADR covers the Go side only. Swift mutation testing is a separate
decision, to be recorded in its own ADR once the tooling question is
settled (bead throwntom-ug9v).

## Context

spe guards test quality with cargo-mutants in three layers (diff-scoped PR
gate, weekly full sweep, local write-time run) because a full Rust run costs
~3 h. The 2026-09-12 spike (docs/spikes/go-swift-mutation-testing/result.md,
bead throwntom-cdlp) measured whether throwntom needs that machinery: a
whole-module gremlins run over the Go tree is 682 mutants in ~3 minutes on a
dev machine at 89.6% killed. The cost problem spe's layering solves does not
exist here. (The same spike also evaluated Swift tooling; those findings
feed the separate Swift ADR.)

## Decision

- **Go: adopt gremlins** (v0.6.0) as a required PR check running the whole
  module every time — no diff scoping, no scheduled sweep, no sharding.
  `--timeout-coefficient 10`; defaults mark every mutant timed-out against
  this suite.
- **Single negative scope** in one config file, shared by CI and local runs.
  Excluded: `tools/` (dev utilities; a bug costs a debugging session, not a
  broken timer) and process bootstrap (`^cmd/[^/]+/main\.go$`,
  `cmd/throwntom/startup.go`), where killing a mutant means process-lifecycle
  tests that mostly restate wiring. The rest of `cmd/throwntom` stays IN
  scope: the Bubble Tea model, theme, and stats handler are tested domain
  logic, not plumbing. Borderline files are arbitrated file-by-file from the
  survivor list — a file earns exclusion only when its mutants are killable
  solely by tests not worth maintaining, recorded with a justifying comment.
- **The bar is zero unexcluded in-scope survivors**, not a kill-rate
  percentage. Known-equivalent mutants are excluded via reviewed config
  changes with justification (spe's equivalence policy). This bar covers
  every non-KILLED status, not just LIVED: an in-scope mutant that is
  LIVED or NOT COVERED fails the gate the same as an excluded-equivalent
  requires a reviewed exclusion; TIMED OUT and NOT VIABLE are reported
  separately and triaged (a real hang vs. an uncompilable schema) rather
  than silently passing. gremlins reports each status distinctly — the
  gate consumes all of them, not just the LIVED count.

## Trade-offs

- **Diff-scoped PR gate + weekly sweep (spe's design) — rejected**: at ~3
  minutes whole-module, the layering buys nothing and adds config, a
  scheduled workflow, and a survivor-capture pipeline to maintain. Whole-
  module on every PR also catches cross-file survivors a diff scope misses.
  gremlins has `-D/--diff` if PR wall clock ever forces a retreat.
- **gomu — rejected for now**: actively developed and works (v0.2.1), but
  young, and its richer operator set applied ~6× gremlins' mutants on the
  same package — more thoroughness than can usefully be burned down at
  adoption time, plus a `.gomu_history.json` dropped in the repo root.
  Revisit once gremlins survivors are at zero.
- **Excluding all of `cmd/` (spe's UI analogy) — rejected**: spe excluded
  iced plumbing that had no economical tests; `cmd/throwntom` already has
  dedicated tests for nearly every file, so a directory-level exclusion
  would discard protection the suite already provides.
- **Accepted cost**: every PR pays the mutation run in parallel with other
  CI jobs; runs are load-sensitive (a saturated machine produced 425 phantom
  timeouts even at coefficient 10), so local runs belong on an idle machine
  and the CI job needs a runner to itself.
