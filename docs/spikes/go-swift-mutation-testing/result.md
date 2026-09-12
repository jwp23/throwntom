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

## Follow-up spike: honest Swift runs under workspace relocation

Bead: throwntom-gz9z.2 · Feeds: throwntom-ug9v (Swift CI adoption)
Run: 2026-09-12 · Tool: ericodx/swift-mutation-testing built from source at
commit f271976 (2026-05-24)

### Question

The first trial's verdicts were invalid because the relocated sandbox breaks
the daemon-spawning tests. What configuration makes the suite pass in the
sandbox, and does an honest run then report a planted survivor as Survived
and the ReconnectBackoff line-44 litmus as Killed?

### Method

Negative-control protocol from the first spike, recreated: copy
`macos/Throwntom` outside the repo, move `StatsSummary.swift` and
`ReconnectBackoff.swift` into `Sources/ThrowntomClient/Stats/` so
`--sources-path` scopes the run to 27 mutants, and change the
`formatDuration(minutes: 60)` assertion to `minutes: 120` so the `>=` → `>`
mutant at `StatsSummary.swift:157` is a true survivor. A second copy is a
`git clone` of the whole repo, so the code-change fixes can be tested with a
real Go module around the package. Verdicts were read from `--output` JSON,
which records `killedBy` per mutant; the console does not.

### How the sandbox breaks the suite

- The sandbox is `$TMPDIR/xmr-<uuid>/`. Every unmutated file, tests
  included, is a **symlink** back to the source tree; only schematized
  sources are real files (`Sandbox/SandboxFactory.swift`, `writeFile`).
- `#filePath` is the compile-time path, i.e. the symlink path under the
  sandbox, so five `deletingLastPathComponent()` calls land in `$TMPDIR`.
  Two tests derive the repo root this way: `DaemonHarness.repoRoot`
  (`Tests/ThrowntomClientTests/TestSupport.swift:147`) and the DESIGN.md
  palette check (`Tests/ThrowntomUITests/DesignTokensTests.swift:28`).
- Relocated baseline: 844 tests, 17 failures across `DaemonClientTests`,
  `UnixSocketTransportTests`, `ReminderNotificationAnswerTests` (the three
  `DaemonHarness` users) and `DesignTokensTests`. Not just the one class
  the first spike named.
- The tool's "baseline" is a warm-up, not a check: `validateSPMBaseline`
  runs `swift test` and discards the result
  (`Execution/MutantExecutor.swift:338-353`, `_ = try?`). Any failing
  suite is a kill (`Execution/SPMResultParser.swift`: nonzero exit + a
  `Test Case ... failed` line → killed). Upstream issue candidate.

### Three fixes that make the suite pass in the sandbox

1. **Tool-side filter, no code change.** `--target` is passed verbatim as
   `swift test --filter <regex>` (`Execution/TestExecutionStage.swift:129-133`),
   and `swift test --filter` accepts a negative lookahead (verified), so it is
   a skip list:
   `--target '^ThrowntomClientTests\.(?!DaemonClientTests|UnixSocketTransportTests|ReminderNotificationAnswerTests)'`
   runs 293 client tests, 0 failures, in the relocated copy. YAML key:
   `test-target` (`Configuration/ConfigurationResolver.swift:35`). The
   tool exposes no `--skip`. Widening to both targets needs
   `DesignTokensTests` in the lookahead too.
2. **Resolve the symlink before deriving the root** — one call at each
   site: `URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()`.
   Zero configuration, and the daemon and DESIGN.md tests then run inside
   the sandbox. It depends on the tool symlinking rather than copying
   (muter copies), so it is a fix for this tool, not for relocation in
   general.
3. **Env-overridable root** (`THROWNTOM_REPO_ROOT` or similar) at the same
   two sites. Not run, but the mechanism is verified: per-mutant test
   processes inherit the tool's environment
   (`Infrastructure/ProcessRunner.swift:65-75`), so exporting the variable
   before invoking the tool reaches the tests. Same cost profile as 2;
   works under any tool that relocates, at the price of a knob nobody sets
   by hand.

### Runs

All on the 27-mutant scope (3 unviable in every run). "filter" = fix 1 in
the outside-the-repo copy; "symlink" = fix 2 in the clone, full suite
including the daemon and UI tests.

| Run | Config | Wall | Killed / Survived / Timeout | Planted 157 | Line 44 (`>`→`>=`) |
|---|---|---|---|---|---|
| 1 | filter, 30 s, 9 workers | 5 m 26 s | 19 / 1 / 4 | Survived | Killed |
| 2 | symlink, 30 s, 9 workers | 6 m 53 s | 18 / 1 / 5 | Survived | **Timeout** |
| 3 | symlink, 120 s, 9 workers | 10 m 43 s | 22 / 2 / 0 | Survived | Killed |
| 4b | filter, 120 s, 9 workers | 7 m 39 s | 22 / 2 / 0 | Survived | Killed |
| 7 | filter, 30 s, 1 worker | 5 m 29 s | 19 / 1 / 4 | Survived | Killed |

- **Both fixes satisfy the acceptance criteria** once the timeout is
  raised: planted survivor Survived, line-44 relational mutant Killed by a
  named `ReconnectBackoffTests` case, no timeouts. At the 30 s default the
  full-suite run reported the litmus mutant as Timeout (run 2).
- The second survivor in runs 3/4b is real: `ReconnectBackoff.swift:18`
  `precondition(registerEvery > 0)` → `>= 0`, which no test exercises.
  Every 30 s run (1, 2, 7) reported that same mutant as **Crash**, a
  false kill; every 120 s run reported it Survived. Applying the mutant
  by hand in the copy builds and passes all 293 filtered tests with exit
  0, so nothing traps. Crash means the run's output carried `Fatal error`
  and no failed-test line (`Execution/TestOutputParser.swift`); a timed-out
  process is reported as Timeout, and a failed rebuild of a
  non-schematizable mutant as Unviable
  (`Execution/IncompatibleMutantExecutor.swift:287-298`), so neither path
  explains it. The tool discards per-mutant output, so the cause was not
  recoverable here. Treat Crash verdicts at the 30 s default as suspect.
- **The 30 s default is too tight; the timeouts are slow suites, not
  hangs or queueing.** The same four `ReconnectBackoff.swift:65/87`
  mutants time out at 30 s with nine workers (runs 1, 2) and with one
  worker (run 7), and all are Killed at 120 s (runs 3, 4b) with no
  increase in survivors. Workers do not help anyway: two concurrent
  `swift test --skip-build` runs in one `.build` serialize on SwiftPM's
  lock (`Another instance of SwiftPM ... is already running ... waiting`),
  which is why run 7's wall clock equals run 1's. Use `--timeout 120`;
  `--concurrency 1` costs nothing and keeps the load off the timeout clock.
- Full suite costs ~27-40% more wall clock than the filtered client
  target (run 2 vs 1, run 3 vs 4b) and, at 120 s, produced the same
  verdicts on this scope. The false-survivor risk of filtering is real in principle
  (a mutant only an integration test can kill would be reported Survived,
  a visible triage item) but the reverse failure, a broken baseline,
  is silent. Filtering fails loud; relocation failed silent.

### Result cache: two defects

- **`--no-cache` disables reads only.** Results are persisted
  unconditionally (`Execution/MutantExecutor.swift:83-84`) to
  `.swift-mutation-testing-cache/` in the package dir, and the next run
  without the flag replays them. Run 4 (identical to run 1 but with
  `--timeout 120`) finished in 17 s with run 1's verdicts, timeouts
  included, and printed the per-mutant progress lines as if it had tested
  them. The cache key is the mutated file content plus the mutant
  (`Cache/MutantCacheKey.swift`); timeout and concurrency are not part of
  it. `Loaded N mutants from cache` prints only when every mutant is
  cached; partial replays are silent.
- **Killed verdicts never invalidate on test edits.** Killer test files
  are stored as absolute paths (`Cache/KillerTestFileResolver.swift`, from
  `TestFilesHasher.testFilePaths`) but the change set is keyed by
  project-relative path (`TestFilesHasher.hashPerFile`), so
  `invalidate(diff:)` (`Cache/CacheStore.swift:93-120`) can never match a
  modified file. Proven: after replacing `ReconnectBackoffTests.swift`
  with an empty class, a cached run (run 5, 5 m 42 s) still reported six
  mutants Killed by tests that no longer existed; the fresh-cache control
  (run 6) reports `ReconnectBackoff.swift:65` `>`→`>=` Survived. Kills
  whose killer class name does not match a file name (e.g.
  `BackoffRegistrationCountTests`) are unresolvable and are correctly
  re-run on any test change, which is why the first spike saw *some*
  refresh. Survived/timeout entries are always re-run.
- This is the "cache replayed stale verdicts" observation from the first
  spike, now with a cause. Do not enable the cache in CI; delete
  `.swift-mutation-testing-cache/` before every run, since `--no-cache`
  does not.

### Recommendation

- **Adopt fix 2 (symlink resolution) in both test files** and keep the
  `--target` lookahead as the CI scoping knob rather than a correctness
  crutch: per-target scoping halves the suite when only the client is
  mutated. Either fix alone satisfies the criteria; fix 2 keeps the
  daemon tests in the kill set at ~27% more wall clock.
- CI invocation for throwntom-ug9v: `--testing-framework xctest
  --concurrency 1 --timeout 120` (120 s is required, not tuning: at 30 s
  the litmus mutant timed out and a true survivor was reported Crash),
  delete the cache dir first, `--output`
  JSON as the artifact (it carries `killedBy`), and keep the negative
  control (planted survivor must be Survived) as a job that runs before
  trusting any score.
- Upstream issue candidates, in order of harm: baseline result discarded;
  cache never invalidated by test edits; `--no-cache` still writes;
  Crash verdicts on a clean mutant at the default timeout (repro above);
  SPM concurrency serialized by the `.build` lock.
