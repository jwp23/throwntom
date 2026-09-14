# ADR-016: Swift Mutation Testing Shards ThrowntomUI and Reports Unviable Mutants Without Gating

Supersedes ADR-015 in part: its one-job-per-target shape, its cost estimate,
and its rule that Unviable mutants are triaged. The rest of ADR-015 stands —
weekly full-scope runs, the negative control, the run parameters, and the
zero-survivor bar for every other status.

## Context

The first full CI run (2026-09-13, run 34779872352, bead throwntom-ug9v)
measured what ADR-015 had estimated from a 3.4k-line local spike:

- `ThrowntomClient`: 337 mutants in 195 minutes on `macos-15`, about 35 s
  each — against an estimate of ~1.3 h.
- `ThrowntomUI`: 1,200 mutants, 651 of them incompatible with the tool's
  shared build, so each pays its own incremental `swift build --build-tests`
  before its tests run. Even at the client's rate that is roughly 12 hours,
  twice the 6-hour GitHub-hosted job limit, so the job was cancelled. `RemoveSideEffects` alone contributes 704 of
  the 1,200 (451 of the 651 rebuilds): inside a SwiftUI view builder each
  child view is a bare call statement, which is what that operator deletes.
- Unviable means a mutant does not compile, so no test can ever kill it.
  The client run had 57. An incompatible mutant is usually found Unviable
  only after its own build fails, so most of those cost build time as well. ADR-015's bar
  required a reasoned allowlist entry for every one.
- throwntom is a public repository. Standard GitHub-hosted runners,
  `macos-15` included, are free and unlimited for public repositories.
  GitHub's Free and Pro plans both cap concurrent macOS jobs at 5, and every
  job at 6 hours.

## Decision

- **`ThrowntomUI` is sharded, with every operator kept.** A generated split
  (`tools/swiftmutantshard`) balances the target's files across shards by
  line count and hands each job slash-anchored `--exclude` patterns for the
  files other shards own, so every file is mutated exactly once. The shard
  count lives in the workflow matrix and starts at 8: discovery with the
  generated excludes partitions all 1,200 mutants either way, but at 6 the
  heaviest shard holds 296 (212 incompatible) against 240 (164) at 8, which
  leaves headroom under the job time limit. It is adjusted from measured job
  times, not re-decided.
  `ThrowntomClient` runs as a single shard of one.
- **View files stay in scope.** The UI suite renders and snapshots views, so
  a mutant that deletes a child view is a gap a test can catch. Operators are
  revisited only once a sharded run has produced real `ThrowntomUI` Survived
  and Unviable counts.
- **Unviable mutants are reported, not gated.** The gate counts them in the
  tracking issue but they do not count against the zero-survivor bar.
  Survived, Crash, Timeout and NoCoverage still gate, and still reach zero by
  a killing test or a reviewed equivalents entry.
- **Progress is logged as it happens.** The tool block-buffers its stdout
  when piped, so a job killed at its time limit would log nothing; it runs
  under `script(1)`, which passes its exit status through.

## Trade-offs

- **Disabling `RemoveSideEffects` for the UI — rejected for now.** It would
  cut the UI run to roughly 500 mutants, but any missing-view gap would go
  unreported. It stays the first lever if measured cost proves the shards
  unworkable.
- **Excluding SwiftUI view files — rejected.** Cheapest ongoing, but it
  stops measuring 34 of the target's 70 files, the ones its render and
  snapshot tests exist for.
- **Line count is a proxy for mutant count.** Shards will be uneven; a
  shard that runs long is fixed by raising the count.
- **Accepted cost:** an estimated 15-20 hours of macOS runner time a week,
  until a sharded run measures it; free on this public repository, with shards beyond the 5-job
  concurrency cap queueing; weekly wall clock may approach 10 hours. If the
  repository ever goes private, this decision needs revisiting.
- **Unviable is no longer driven to zero.** A rise in Unviable costs build
  time without failing anything; the count in the tracking issue is the
  only signal.
