# ADR-017: Fork swift-mutation-testing Into a Public jwp23 Repository, Fix First, Then Improve

Supersedes ADR-015 in part: its trade-off that the tool "may need patching
or replacing" and its "revisit once issues #66 and #69 are closed upstream"
condition on the diff-scoped PR gate. The rest of ADR-015 and all of ADR-016
stand: weekly full-scope runs, the negative control, the run parameters, the
per-target shards and the zero-survivor bar.

Sequenced after the Swift survivor triage (throwntom-gz9z.1) finishes;
nothing here changes how that triage runs.

## Context

ADR-015 adopted ericodx/swift-mutation-testing at f271976 knowing it was
young and would need patching. Three days of Swift survivor triage
(throwntom-gz9z.1, throwntom-gz9z.6) measured how much:

- The startup sweep, `SandboxCleaner.removeOrphaned()`, runs before argument
  parsing (`SwiftMutationTesting.swift:7`) and deletes every `xmr-*`
  directory in the shared temporary directory with no ownership check
  (`Sandbox/SandboxCleaner.swift:24-35`). Any second invocation by the same
  user wipes a live run, which then reports Unviable with exit 0 or dies
  with no report. `TMPDIR` does not isolate runs. Local triage is therefore
  strictly one run at a time (throwntom-gz9z.4, bd memory
  swift-mutation-testing-shared-tmpdir).
- After a mutant times out, `killEscapedChildren` walks every process on the
  machine and SIGKILLs any whose arguments contain the sandbox name
  (`Infrastructure/SPMProcessLauncher.swift:45-70`), about five seconds
  later, corrupting whichever other mutant is then in flight. throwntom
  answers this with two runs per file merged by `tools/swiftmutantsgate`
  (throwntom-tszi, docs/decisions/swift-mutation-timeout-poisons-a-later-
  mutant.md). The same sweep makes `--concurrency` above 1 unsafe
  (throwntom-ufqt, throwntom-2dsf).
- `--no-cache` disables cache reads but still writes, and Killed verdicts
  are never invalidated by test edits (upstream #67, #68); the cache
  directory is deleted before every run by rule.
- Per mutant the tool runs `swift test --skip-build` in the sandbox
  (`Execution/TestExecutionStage.swift:129`), the mutant selected by the
  `__SWIFT_MUTATION_TESTING_ACTIVE` environment variable (line 142), with a
  fixed timeout and no fail-fast. Workers above 1 queue on SwiftPM's build
  lock (upstream #70). A full ThrowntomClient suite is about 117 s.
- Some files schematize as all-Unviable under Swift 6.4, root cause unknown
  (throwntom-gz9z.6.2).

Upstream is dormant: no commits since f271976 (2026-05-24), five issues
filed 2026-09-12 (#66-#70) unanswered, the sandbox defect held unfiled by
ruling on throwntom-gz9z.4, and the only active fork (dsifry, 27 commits)
is Xcode and simulator work. throwntom already carries a fork's worth of
workarounds outside the tool: swiftmutantsgate's merge mode,
`macos/mutation-control.sh`, `macos/mutation-control-racetest.sh`, the
cache rule and the one-run rule. Each is a place for a vacuous verdict to
hide, and the triage hit that repeatedly.

The base measured well enough to keep: 5,689 lines of Swift 6 in small
layered modules, 11,411 lines of tests, one dependency (swift-syntax).
Every defect above lives in the process and sandbox plumbing. The
schematized discovery over swift-syntax, the hard part, works.

Alternatives measured the same day:

- **muter** (563 stars, last commit 2026-07-21): its broken piece is the
  hard piece. Schemata are generated and never applied because the mapping
  is keyed on syntax-node identity across a re-parse (muter #307, open).
  Ten dependencies, an HTML reporter and iOS simulator plumbing throwntom
  would never use, and four operators, a strict subset of ericodx's seven.
- **From scratch**: a purpose-built SPM-only, XCTest-only tool is the
  ericodx code minus Simulator and Cache, about 4,000 lines, most of it
  swift-syntax discovery and schematization that would be re-derived, plus
  process-lifecycle plumbing whose subtleties took the gz9z.6 epic a week
  to learn.

## Decision

- **Fork ericodx/swift-mutation-testing at f271976 into a public
  repository under jwp23, keeping the upstream remote.** The fork has its
  own beads database; its work is tracked there, not in throwntom.
  throwntom's weekly workflow
  (`.github/workflows/swift-mutation-weekly.yml:29,50-51`) and the local
  build move to the fork's repository and a pinned SHA once the first
  correctness fix lands.
- **Fix first, in this order:** the startup sweep removes only sandboxes
  whose owning process is dead; escaped-child cleanup kills only
  descendants of the run's own test process; `--no-cache` disables writes
  as well as reads, or the cache module is removed. The two-run race test
  with revert-fail-restore proves the sandbox and escaped-child fixes and
  becomes a required check in the fork's CI. The cache fix is proved
  separately: a direct test asserting `--no-cache` creates or modifies no
  cache entries if the cache module remains, or its removal if it does
  not.
- **Then improve, each measured against a baseline before merge:** run the
  built `.xctest` bundle directly instead of `swift test --skip-build`,
  one sandbox per worker, which removes the build lock; likely-killer tests
  first with the full suite only on survival; per-mutant timeout as a
  coefficient of the baseline duration; fail-fast on the first failure;
  coverage-based NoCoverage skipping; a diff-scoped mutant filter that
  takes a line set, with a `--since <ref>` convenience over
  `git diff -U0`, where zero mutants in scope is an explicit pass.
- **Diff scope covers changed tests, not only changed sources.** A PR that
  only adds or edits a test must still run mutants: those in the source
  files the changed test files map to, and those a previous full report
  recorded as killed by a test in a changed file. The gate is mechanical;
  it does not rely on an agent having done the revert-fail-restore by
  hand. The mechanism is chosen in the PR-check ADR.
- **throwntom's workarounds are retired or redone as the fix that makes
  each unnecessary lands, not left in place.** The two-run merge in
  `tools/swiftmutantsgate` and the `--disable-mutator` second run go with
  the child-kill fix; the local one-run lock in `macos/mutation-control.sh`
  and the race test go with the sandbox fix, the race test moving into the
  fork's CI; the delete-the-cache rule goes with the cache fix; the
  hand-verified own-Timeout and trap-Crash categories in
  `.swift-mutation-equivalents.json` (24 of its 43 entries today) and the
  unexcluded gate violations left because no tool filter could isolate them
  are re-run by the fixed tool and removed once it reports them Killed.
  Those categories are temporary: an exclusion exists because a mutant is
  provably equivalent, never because the tool cannot observe the kill. A
  mutant the fixed tool still cannot see is a tool defect to fix in the
  fork, not an entry to keep. The negative control stays: ADR-015 requires
  it regardless of tool.
- **Correctness patches are offered upstream as pull requests against the
  open issues.** If the maintainer returns, throwntom re-pins to upstream
  and the fork is archived.
- **The diff-scoped Swift PR check is a separate decision.** It gets its
  own ADR when that item is picked up. ADR-015's deferral stands until
  then, minus the upstream-closure condition, which this ADR replaces
  with "once the fork's fixes and direct-bundle execution have landed".

## Trade-offs

- **Ownership, accepted.** A Swift codebase we did not write, maintained
  by us for as long as we mutation-test Swift. That was already true at
  the pin; the fork only makes it honest. The fork's own tests are the
  10,000 lines we did not have to write.
- **Mutation-testing the tool would not have caught these, so it is not
  the gate.** Every defect is a cross-process or cross-invocation
  behaviour; the unit tests exercise each function against fakes, so a
  self-run score would look excellent and mean nothing. The race test is
  the check that matters, hence it is required in CI. Established tools
  (Stryker, PIT, muter) do self-run; ericodx added and removed a score
  badge within a day.
- **Forking muter, rejected.** Fixing its schemata application means
  fixing the core of a codebase we do not know, then carrying ten
  dependencies against this project's minimal-dependency rule. Its larger
  community did not fix a "tests unmutated code" defect in two months.
- **Writing from scratch, rejected.** It is a subtraction from the fork,
  not a rewrite. Deleting Simulator and Cache from the fork is available
  later as cleanup if they get in the way.
- **What parallelism buys, bounded.** Inside one run, concurrency above 1
  is worthless for SPM until the bundle runs directly. Across runs on one
  Mac, expect roughly 2x on triage wall clock, limited by cores and by
  the timeout margin throwntom-aqna already calls thin; running two at
  once means the CI value of `--timeout 240` locally too.
- **Fixed cost of a future PR check does not shrink.** Each run still
  pays one schematized build plus the baseline run before the first
  mutant; the improvements shrink the per-mutant cost, not that floor.
- **Test-only PRs must not pass vacuously.** Three mechanisms can put
  mutants in scope for a changed test file, cheapest first: a naming
  convention plus override map from test file to source file, at file
  granularity; the `killedBy` field of the last full JSON report, which
  names the test that killed each mutant and so identifies the mutants a
  changed test is responsible for; and per-test coverage, which is what
  Stryker's `--since` uses and is the only one that also credits a new
  test with the mutants it reaches. The first two need nothing the tool
  does not already record. The revert-fail-restore rule stays as the
  agent-side check; it is not the gate.
