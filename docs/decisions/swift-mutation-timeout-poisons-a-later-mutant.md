# A swift-mutation-testing timeout SIGKILLs a later mutant's run

## Decision

A mutation report is trusted only where it contains no `Timeout` mutant.
Triaging a file whose gated set contains a genuine Timeout takes two runs:

1. the file-scoped run, as ADR-015 describes it;
2. a second run over the same file with every operator that timed out disabled
   (`--disable-mutator RemoveSideEffects`, say). That run has no Timeout in it,
   so nothing in it can be poisoned.

Both reports go to `tools/swiftmutantsgate`, which merges them by mutant
identity — file, line, column, mutator, replacement — and keeps the verdict from
the fullest observation: a kill ahead of a `Crash`, a `Crash` ahead of an
`Unviable`. It then lists the verdicts the reports do not settle between them: a
`Crash` or `Unviable` no timeout-free run confirms, and a mutant one run killed
and another survived.

That last one is not this defect at all. A SIGKILLed run exits non-zero, so no
run can invent a `Survived`; both halves come from a run that finished, and
nothing in the reports says which was right. It is a flaky or order-dependent
test, so the gate keeps the **survival** and fails on it — ADR-015's bar is zero
unexcluded survivors, and a kill nobody can reproduce is not a kill. The note
beside it is what tells a reader that this is a contradiction to settle by hand
rather than a mutant no test ever killed.

Two conditions on the second run. Delete `.swift-mutation-testing-cache` first:
the cache replays a stored Crash verbatim, so the second run would otherwise
agree with the first for the wrong reason. And run both against the same tree —
a mutant's identity includes its line and column, so an edit above it between
the runs leaves the merge matching nothing. That fails safe (the reports are
then merely concatenated, as before) but it silently buys nothing.

A mutant that shares its file *and* its operator with a Timeout mutant cannot be
split off by any filter the tool has. That one is verified by hand — the
replacement applied to the source, the suite run, the outcome recorded on the
bead — and never written into `.swift-mutation-equivalents.json`.

## What the equivalents file legitimately holds

`.swift-mutation-equivalents.json` covers three shapes, not one:

1. **Proven equivalent.** Behaviorally identical to the original, provably from
   the code — no test can ever distinguish the two, regardless of the tool.
2. **Genuine own-Timeout, hand-verified kill.** A mutant with a real Timeout
   (not a poisoning artifact) that a fast test provably kills by hand, where
   the tool cannot observe that because it has no per-test scope: breaking
   something widely shared makes the *whole* suite exceed the tool's timeout
   budget, so the run it belongs to can never finish and report Killed.
3. **Genuine trap-Crash, hand-verified kill.** A mutant that causes a
   deterministic Swift runtime trap (precondition, array-bounds, force-unwrap)
   in a file with no Timeout mutant anywhere in its own gated set — which rules
   out the poisoning mechanism above, since poisoning needs a Timeout mutant
   present to schedule the delayed kill. A hard trap crashes the whole test
   process, which the tool's parser can never distinguish from a clean
   pass/fail run, so "Killed" is permanently unobservable for it — not just
   unobserved this run.

What stays out, always: a Crash-status mutant that shares *both* file and
operator with a genuine Timeout mutant. No filter the tool has (`--sources-path`,
`--exclude`, `--operator`, `--disable-mutator`) can isolate that one from the
poisoning mechanism this decision describes, so its Crash verdict is not
trustworthy by the reasoning above — it is a gate violation to record on the
bead, verified by hand, and left unexcluded.

## For the epic's bd design field (paste verbatim)

`.swift-mutation-equivalents.json` holds three legitimate categories, not one:
proven equivalents (behaviorally identical to the original, provably from the
code); genuine own-Timeout hand-verified kills (a real, non-poisoning Timeout
that a fast test provably kills by hand, unobservable to the tool because it
has no per-test scope); and genuine trap-Crash hand-verified kills (a
deterministic runtime trap in a file with no Timeout mutant anywhere in its
own gated set, so the Crash cannot be poisoning — a hard trap crashes the
whole process, which the parser can never tell apart from a clean pass/fail
run). What must never go in the file: a Crash-status mutant that shares both
file and operator with a genuine Timeout mutant, since no tool filter can
isolate it from the poisoning mechanism — that shape is verified by hand,
recorded on the bead, and left as an unexcluded gate violation. See
docs/decisions/swift-mutation-timeout-poisons-a-later-mutant.md for the full
mechanism and worked examples of all three categories.

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
  gated at all, if the kill landed before the run's first test marker and left
  some other output behind, build chatter being the usual case
  (`SPMResultParser.swift:9` reports an empty output as a Crash instead).
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
- The weekly run reports Crash counts inflated by the same mechanism, and
  Unviable counts that may hide a live mutant the same way. The gate names both
  wherever a report carries a Timeout and nothing else confirms the verdict,
  which is as far as this goes without a tool change. One Timeout spoils at most
  one run, but no report records which, so every unconfirmed verdict from such a
  run is listed.
