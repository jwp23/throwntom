# A swift-mutation-testing timeout SIGKILLs a later mutant's run

## Decision

A mutation report is trusted only where it contains no `Timeout` mutant.
Triaging a file whose gated set contains a genuine Timeout takes two runs:

1. the file-scoped run, as ADR-015 describes it;
2. a second run over the same file with every operator that timed out disabled
   (`--disable-mutator RemoveSideEffects`, say). That run has no Timeout in it,
   so nothing in it can be poisoned.

Both reports go to `tools/swiftmutantsgate`, which merges them by mutant
identity — file, line, column, mutator, replacement — and keeps the verdict
from the fullest observation, a kill first of all. Delete
`.swift-mutation-testing-cache` before each run: the cache replays a stored
Crash verbatim, so a second run would otherwise agree with the first for the
wrong reason.

A mutant that shares its file *and* its operator with a Timeout mutant cannot be
split off by any filter the tool has. That one is verified by hand — the
replacement applied to the source, the suite run, the outcome recorded on the
bead — and never written into `.swift-mutation-equivalents.json`, which is for
mutants no test can distinguish, not for mutants the harness cannot report.

## Rationale

- **Measured**, 2026-09-14, throwntom-tszi, against a five-mutant fixture
  package built for the purpose. Mutant 1 parks the suite and is reported
  Timeout. Mutant 2, whose test fails after 10 s, is reported **Crash** — after
  running for 5.2 s. Mutants 3-5 are Killed. Moving the same failure to 2 s
  moves the Crash: mutant 2 finishes and is Killed, and mutant **3** is the one
  reported Crash. The defect is not "the mutant after a timeout"; it is
  "whichever test run is in flight five seconds after a timeout fires". It reads
  as the successor only because a run of this package's suite takes longer than
  five seconds.
- **Mechanism**, in the tool at the pinned f271976: `onTimeout` sends `SIGTERM`
  to the timed-out process group, then from a detached task sleeps five seconds
  and calls `killEscapedChildren`
  (`Sources/SwiftMutationTesting/Infrastructure/SPMProcessLauncher.swift:32-40`).
  That function SIGKILLs every process on the machine whose argv or environment
  merely *contains* the sandbox directory's name (`:45-73`; confirmed here by
  killing an unrelated `tail -f` that named a `/tmp/xmr-…` path). Every mutant of
  one invocation runs in one sandbox
  (`Execution/MutantExecutor.swift:49`, `Execution/TestExecutionStage.swift:144`),
  so the run in flight matches, dies, and exits non-zero with output the parser
  reads as a crash (`Execution/Parsing/TestOutputParser.swift:32`,
  `Execution/Parsing/SPMResultParser.swift:8`) — or as Unviable, which is not
  gated at all, if the kill landed before the first test printed.
- **One mutant per invocation would be a complete fix**, since each invocation
  makes its own sandbox, but the tool can be scoped by file (`--sources-path`,
  substring `--exclude`) and by operator (`--operator`, `--disable-mutator`) and
  by nothing finer (`CLI/CommandLineParser.swift:144-150`,
  `Discovery/Pipeline/FileDiscoveryStage.swift:69`).
- **Patching the tool is the real cure** — reap the timed-out process group
  before the next mutant starts, or scope the sweep to the run that timed out —
  but it is pinned by ADR-015 and shared with
  `.github/workflows/swift-mutation-weekly.yml`. Re-pinning it is a decision
  about shared infrastructure, not a triage step, so it is not taken from
  inside a triage bead.
- The weekly run reports Crash counts inflated by the same mechanism. The gate
  now says so where both statuses meet in one report, which is as far as this
  goes without a tool change.
