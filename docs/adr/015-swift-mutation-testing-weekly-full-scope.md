# ADR-015: Swift Mutation Testing Runs Weekly, Full-Scope, Behind a Negative Control

This ADR covers the Swift side; ADR-014 covers Go.

## Context

The 2026-09-12 spikes (docs/spikes/go-swift-mutation-testing/result.md,
beads throwntom-cdlp and throwntom-gz9z.2) found one live Swift tool,
ericodx/swift-mutation-testing (3 stars, created 2026-03), and showed both
why its first trial was worthless and how to make it honest:

- It builds in a `$TMPDIR` sandbox that symlinks test files back to the
  repo, so a test that derives the repository root from `#filePath` lands
  in `$TMPDIR`. Two tests do: the daemon harness in
  `Tests/ThrowntomClientTests/TestSupport.swift` and the DESIGN.md palette
  check in `Tests/ThrowntomUITests/DesignTokensTests.swift`. 17 of 844
  tests then fail in every per-mutant run.
- The tool discards its baseline result and counts any failing suite as a
  kill, so that trial reported 260 killed, 0 survived for 333 mutants. A
  planted survivor was reported Killed.
- With the suite passing in the sandbox and `--timeout 120`, the planted
  survivor is reported Survived and the line-44 litmus Killed. At the 30 s
  default a genuine survivor was reported Crash in every run.
- Cost is the inverse of Go's: one build, then a full XCTest run per
  mutant (~10 s). `ThrowntomClient` alone is ~55 min; the whole package is
  multi-hour, on macOS runners.
- The result cache replays stale Killed verdicts after test edits and
  `--no-cache` still writes. Five defects are filed upstream (#66-#70).

spe answers a similar cost profile with a diff-scoped PR gate plus a
weekly full sweep. The Swift tool has no diff scoping (`--in-diff`) and no
sharding; scoping is `--sources-path` plus substring `--exclude`.

## Decision

- **Adopt swift-mutation-testing, weekly and full-scope, not as a PR
  gate.** A scheduled workflow mutates the whole in-scope package, one job
  per target with its own `--sources-path`, and files or refreshes a
  single labelled tracking issue listing survivors, closing it when a run
  comes back clean. The issue is transient; survivors are triaged into
  beads on a regular cadence, the same shape as the SonarCloud drift
  audit. No diff-emulated PR gate until in-scope survivors are at zero
  and the upstream honesty defects are fixed.
- **The suite must pass under relocation.** Both repo-root derivations
  resolve symlinks before walking up (`resolvingSymlinksInPath()` on
  `#filePath`). Tests must not derive the repository root from
  `#filePath` alone. Integration tests stay in the kill set; the
  `--target` test filter is a scoping knob, not a correctness fix.
- **Run parameters are policy, not tuning:** `--timeout 120`,
  `--concurrency 1`, the cache directory deleted before every run, the
  JSON report kept as the artifact because only it records `killedBy`.
- **A negative control gates every score.** Each run first mutates a
  scratch copy with one assertion removed and must report that mutant
  Survived; otherwise the run fails loudly and files no score. This is
  what stops a repeat of the 0-survivors artifact.
- **The bar is zero unexcluded in-scope survivors**, as in ADR-014.
  Equivalent mutants are excluded through reviewed config with
  justification. Timeout, Crash and Unviable are triaged, not passed.

## Trade-offs

- **Diff-scoped PR gate (spe's layer 1) — deferred, not rejected.** It is
  emulable by excluding every in-scope file not in the PR diff, but at
  file granularity (a one-line edit pays for its whole file), on paid
  macOS minutes, and with a tool whose false Timeout blocks a PR and
  whose false Crash passes it silently. Revisit once survivors are zero
  and issues #66 and #69 are closed upstream.
- **Filtering out the daemon tests instead of fixing the root
  derivation — rejected.** It is cheaper (~27-40% less wall clock) and
  fails loud, but mutants only an integration test can kill would be
  reported Survived every week.
- **Symlink resolution instead of an env-overridable root — accepted
  risk.** It works because this tool symlinks; a tool that copies would
  break it again. An env knob works everywhere but is a setting nobody
  sets by hand. Revisit if the tool changes.
- **Accepted cost:** roughly three hours of macOS runner time a week
  across two parallel jobs, more as the package grows; a young tool (3
  stars) that may need patching or replacing; and no protection on
  individual PRs beyond the existing test suite.
