# Spike: mutation testing for Go and Swift

Bead: throwntom-cdlp · Feeds: throwntom-ewx1 (Go adoption), throwntom-jkkg
(survivor triage), throwntom-ug9v (Swift path decision)
Run: 2026-09-12

## Question

spe runs cargo-mutants in three layers (diff-scoped PR gate, weekly full
sweep, local write-time run) because a full Rust run costs ~3 h. Does
throwntom need that machinery, or are Go and Swift mutation runs cheap
enough to run whole-scope on every PR? And do viable tools exist for each
language?

## Method

Install each candidate tool, run it against this repo (whole Go module;
targeted Swift files/modules), and time it on an M-series dev machine.
For Swift correctness, use `Sources/ThrowntomClient/ReconnectBackoff.swift`
as a litmus: `ReconnectBackoffTests` asserts the exact delay sequence from
the first failure, so a relational mutant at the `failures > 1` guard
(line 44) must be killed by any working tool.

## Results — Go

| Tool | Scope | Mutants | Wall clock | Outcome |
|---|---|---|---|---|
| gremlins v0.6.0 | `internal/engine` | 39 | 17 s | 87.2% killed, 5 lived |
| gremlins v0.6.0 | whole module | 682 | 3 m 07 s | 89.6% killed, 66 lived, 42 not covered |
| gomu v0.2.1 | `internal/engine` | 226 | 43 s | 75.5% score, 54 lived |

Both tools work against Go 1.27. Findings that matter for adoption:

- **gremlins' default timeout is broken for this suite**: every mutant
  reports timed-out. `--timeout-coefficient 10` fixes it (39/39 then run
  normally).
- **A whole-module run is cheap enough to fit inside a PR check on this
  dev machine**: 3 m 07 s locally. CI runner performance is not yet
  measured — see the load-sensitivity note below — but the cost problem
  spe's diff-scoping and weekly-sweep layers solve does not look like it
  exists here.
- gremlins is coverage-guided (uncovered mutants are reported without
  running tests) and has native `-D/--diff` if PR-scoped runs are ever
  wanted.
- gomu (v0.2.1, 44 stars, active through 2026-07) applies ~6× the mutants
  of gremlins on the same package — richer operators, but proportionally
  more triage noise — and writes `.gomu_history.json` into the repo root.
- **Runs are load-sensitive.** A second whole-module run, captured while a
  Swift build saturated the machine, reported 425 timeouts even with
  `--timeout-coefficient 10` — its per-file survivor numbers are garbage.
  The headline numbers above are from the first run on a quiet machine.
  A per-file survivor distribution needs a clean idle-machine rerun
  (tracked on throwntom-jkkg); don't schedule the CI job's conclusions off
  a loaded box.

## Results — Swift

### muter: not viable

- **v16 (Homebrew, 2023 release)**: mutation schemata generates
  uncompilable Swift on this codebase — a `return <expr>` injected into a
  void function (`ReminderResponder.swift`), aborting the run.
- **main (2026-07)**: runs to completion but never activates the mutants
  it inserts. On the litmus file it reported 0/4 killed; per-mutant XCTest
  logs show the full 844-test suite passing with no rebuild and no source
  change per mutant. The line-44 relational mutant that the tests provably
  kill "survived". Harness defect, not weak tests.
- Incidental: muter copies the project (including a stale `.build/`, which
  then fails to compile — delete it first) to a `<name>_mutated` sibling
  directory inside the repo, and its spawned build could not find
  `codesign` (SwiftPM's entitlement step) under muter's child environment.

### ericodx/swift-mutation-testing

Very young (created 2026-03, 3 stars, active) but built against modern
Swift, supports SPM + XCTest/Swift Testing, schematization with a
build-once/test-per-mutant runtime switch, result caching, and Stryker/
Sonar report formats. Trial on `Sources/ThrowntomClient` (build from
source; the Homebrew tap is untrusted by default):

| Scope | Mutants | Wall clock | Outcome |
|---|---|---|---|
| `Sources/ThrowntomClient` (3.4k LOC) | 333 | 55 m 05 s | reported 94.2% — 260 killed, 0 survived, 16 timeouts, 57 unviable — but see below: the kill verdicts are invalid |

- **The 0-survived headline is an artifact — do not trust this run's
  verdicts.** The tool copies the package to a temp workspace and
  compiles there; `DaemonHarness.repoRoot` is `#filePath`-derived
  (`Tests/ThrowntomClientTests/TestSupport.swift`), so in the relocated
  workspace it resolves outside any Go module, `go build ./cmd/throwntomd`
  fails, and every `DaemonClientTests` case fails in every per-mutant run
  — baseline included. The tool counts a failing suite as a kill and
  never flags the broken baseline, so every viable mutant reports Killed.
  Proven by negative control: with the `formatDuration` 60-minute
  boundary assertion removed in a scratch copy, the then-genuinely-
  surviving `>=` → `>` mutant was still reported Killed (with and without
  cache). muter's copy is a sibling directory *inside* the repo, which is
  why its baseline passed.
- Consequences: (a) any adoption must make daemon-spawning integration
  tests survive workspace relocation — e.g. skip them in mutation runs
  or resolve the repo root via an overridable env var — and prove one
  planted survivor is reported Survived before trusting a run; (b) the
  missing baseline sanity check is worth filing upstream.
- Timing and mechanics below remain valid: schematization, per-mutant
  cost, unviable handling, and the cache observation (a cached rerun
  returned in 20 s but did not notice changed *tests* — verify cache
  invalidation before enabling it in CI).
- **Cost shape is the opposite of Go's.** Schematization means one build,
  but each mutant still pays a full XCTest suite run (~11–14 s), so
  3.4k LOC costs ~55 min. `ThrowntomUI` is 5.9k LOC; whole-package runs
  land in the multi-hour range — Swift needs spe-style scoping/cadence
  (diff-scoped or scheduled), not Go's whole-scope-per-PR.
- 57 unviable mutants (schemata that don't compile) are detected and
  reported rather than aborting the run — the failure mode that kills
  muter v16 outright.
- 16 timeouts need triage (real hangs vs. too-tight 30 s SPM default).
- Caveats: project created 2026-03, 3 stars; no per-file scoping flag
  (`--sources-path` + repeatable `--exclude` is the scoping mechanism).

## Recommendation

- **Go: adopt gremlins now** (throwntom-ewx1). Whole-module required PR
  check, `--timeout-coefficient 10`, negative scope in one config file,
  zero-unexcluded-survivors bar — spe's principles without its diff/weekly
  machinery. Revisit gomu once gremlins survivors are at zero.
- **Scope** (ruled 2026-09-12): exclude `tools/` and process bootstrap
  (`cmd/*/main.go`, `cmd/throwntom/startup.go`); keep the rest of
  `cmd/throwntom` in scope — the Bubble Tea model, theme, and stats
  handler are tested domain logic, unlike spe's excluded UI plumbing.
  Borderline files are arbitrated file-by-file by the clean rerun's
  survivor list, not by a directory rule.
- **Swift: ericodx/swift-mutation-testing is the only live candidate,
  but its trial verdicts are invalid** — the relocated workspace breaks
  `DaemonHarness.repoRoot`, the suite fails in every run, and the tool
  silently counts that as kills (no baseline check). Adoption
  (throwntom-ug9v) must first make the suite pass under relocation for
  mutation runs, then rerun and prove a planted survivor is reported
  Survived. At ~10 s+/mutant it needs spe-style scoping and cadence
  rather than whole-scope PR runs, and its youth (3 stars, 2026-03) is
  real adoption risk. muter is off the table until its activation defect
  is fixed upstream.
