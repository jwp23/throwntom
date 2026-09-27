# ADR-018: Swift Mutation Testing Excludes Pass-Through Files by Scope, Not by Equivalents Entry

Extends ADR-015, which set the Swift bar and the equivalents file but never
defined a negative scope, and ADR-017, whose rule on what an exclusion is
this ADR keeps unchanged. Nothing in either is reversed. ADR-014 already
made this decision for Go; this is the Swift half of it.

## Context

ADR-014 gave the Go run two mechanisms: a file-level negative scope in
`.gremlins.yaml` (`exclude-files`: dev tools and process bootstrap, "where
killing a mutant means process-lifecycle tests that mostly restate
wiring") and a per-mutant allowlist, `.gremlins-equivalents.json`, for
mutants proven equivalent. ADR-015 gave the Swift run only the second.
Everything below follows from that gap.

Swift survivor triage (throwntom-gz9z.1, throwntom-gz9z.6.3) kept meeting
one shape of mutant, in two forms, that neither a test nor an equivalence
proof can dispose of:

- **The test process cannot execute the line.**
  `UNUserNotificationCenter.current()` refuses a process without an app
  bundle: a test that calls `ReminderResponder.start()` aborts on its first
  statement (`ReminderResponder.swift:47`) with an uncatchable
  `NSInternalInconsistencyException`, mutated or not, so nothing after it
  is reachable by any XCTest. `SystemReminderPresenter.swift:41-58` and
  `SystemNotificationInspector.swift:44-46` are the same call. The
  delegate methods at `ReminderResponder.swift:202-217` take a
  `UNNotificationResponse` and a `UNNotification`, which declare `init`
  `NS_UNAVAILABLE`, so no test can construct an argument to call them
  with.
- **The line runs, but its effect is a real side effect with no in-process
  oracle.** `NSWorkspace.shared.open(url)` (`ReminderResponder.swift:157`),
  `SMAppService.openSystemSettingsLoginItems()`
  (`SMAppServiceRegistrar.swift:52`), `NSSound.beep()`
  (`DaemonDispatch.swift:93`, and the `alert` default closures of `NewTaskRow.swift:22`,
  `LunchEntryRow.swift:16`, `MeetingEntryRow.swift:16`,
  `SnoozeEntryRow.swift:15`), `AccessibilityNotification.Announcement.post()`
  (`SpeechAnnouncer.swift:22`). Deleting the call is a real behaviour change
  — a window does not open, a sound does not play — that a test can only
  observe by opening the window or playing the sound, with nothing to
  assert against afterwards.

Triage handled the two forms inconsistently, because the only mechanism it
had was the wrong shape. Eight entries reached `main` in
`.swift-mutation-equivalents.json` under the wording "proven equivalent for
testing purposes" (`SMAppServiceRegistrar.swift:52`,
`ReminderResponder.swift:48`, `49`, `50`, `51`, `157`, `203`, `212`), four
more sit on `test/swift-mutants-views` as "not a behavioral-equivalence
claim", and throwntom-gz9z.1.11, .1.12, .1.16 and .1.20 refused to write
the same kind of entry and left their mutants gated instead. The refusals
were right: docs/decisions/swift-mutation-timeout-poisons-a-later-mutant.md
defines the file's first category as *behaviorally identical, provably from
the code*, and ADR-017:119-122 states the rule outright — an exclusion
exists because a mutant is provably equivalent, never because the kill
cannot be observed. "No XCTest can observe it" is that sentence with the
tool's name changed.

Two of the entries throwntom-gz9z.6.3 grouped with these are not this
shape. `SocketConnection.swift:54` deletes a statement in a branch that 250
probes could not reach; unreachable code has no behaviour to differ, which
is equivalence. `ReconnectBackoff.swift:18:32` (`>=` for `>`) differs from
the original only at `registerEvery == 0`, an input the precondition on
that line forbids; two functions that agree on every input in their domain
are equivalent. Both stay, with reasons that say so rather than "no test
can reach".

The project already names the files this ADR is about.
`sonar-project.properties:19` excludes from coverage measurement
`SystemNotificationAuthorizer.swift`, `SystemNotificationInspector.swift`,
`SystemReminderPresenter.swift`, `ThrowntomApp.swift` and
`BundledMainAppService.swift`, each with a header saying the same thing:
a pass-through to an SDK the test process cannot reach, with everything
that decides anything behind a protocol elsewhere
(`SystemReminderPresenter.swift:5-9`, `SystemNotificationInspector.swift:9-16`).
That list also still names `BundledAgentService.swift`, which no longer
exists.

## Decision

- **The Swift run gets a file-level negative scope, as the Go run has.** A
  file is excluded when it is a *pass-through*: it holds bare calls into an
  SDK that a test process cannot reach or must not invoke, and no decision
  of its own — no branch a test could take the other way. The list is
  reviewed config with a reason per file, the shape `.gremlins.yaml`
  already has. It is fed to the tool as `--exclude` patterns beside the
  ones `tools/swiftmutantshard` prints for sharding
  (`.github/workflows/swift-mutation-weekly.yml:203-212`), and the
  equivalents gate keeps reading the same report it does today.
- **Coverage measurement and mutation scope share one list.** The files
  excluded from mutation are the files excluded from coverage, for the
  same reason, and one config is the source of truth for both. A file
  that earns one exclusion has earned the other; a file that has grown a
  decision has lost both.
- **The equivalents file holds no fourth category.** Its three categories
  stand as the decision doc records them, and ADR-017's rule stands: an
  entry is a proven equivalence, or one of the two hand-verified-kill
  shapes that exist only until the fork can observe the kill. "No test can
  observe it", in any wording, is not a reason. The eight entries on `main`
  that say so are removed as the code they name is moved, and the four on
  `test/swift-mutants-views` are not merged.
- **A line the test process cannot run lives in a pass-through file, and a
  line whose effect has no oracle gets there through a seam.** These are
  one policy with two mechanical remedies:
  - *Unreachable by any test process:* relocate the line.
    `ReminderResponder.swift:47` moves behind the `ReminderPresenter`
    protocol, so that `start()` becomes callable from a test and lines
    48-51 are killed rather than excused (PR #220, unmerged as this is
    written, already carries that seam as `claimNotificationDelegate` and
    drops the four entries). The two
    `UNUserNotificationCenterDelegate` methods move to an extension in a file of their own that
    forwards to `respond(to:then:)` and `presentationOptions`, which stay
    in scope. `SystemReminderPresenter.swift` splits: the
    `UNUserNotificationCenter` calls become a pass-through, and the
    `NSApp` attention and window logic, which decides (the idempotency
    guard at `SystemReminderPresenter.swift:69`) and which
    throwntom-gz9z.1.11 killed five mutants in, stays in scope.
  - *Reachable, real effect, no oracle:* add the seam the project already
    uses (`ConfigFile.swift:9`'s `opener`, the entry rows' `alert`
    closure), then move the SDK call the default closure makes into a
    pass-through. Every call site is then a mutant a spy kills; the one
    real line is out of scope by rule.
- **Both exclusion lists are the last resort, in a fixed order.** A gated
  mutant is disposed of by the first of these that applies, and a triage
  report says which and why the earlier ones did not: a killing test; a
  seam that makes one; a split that moves the decision out of a file that
  is otherwise pass-through; an equivalents entry, for a mutant that is
  provably equivalent; and only then the scope list, for the file that has
  nothing left in it but bare SDK calls. A file enters the list because the
  earlier steps have already emptied it of everything a test could kill,
  not because they looked expensive. The list is expected to stay at the
  handful of files `sonar-project.properties` names today plus the
  pass-throughs the relocations above create; a file that would grow it
  beyond that is a file to split.
- **A pass-through holds no decisions.** That is what makes file-level
  exclusion safe and what review checks when a file is added to the list
  or edited afterwards. `swift-review` is the gate.

## Trade-offs

- **Coarser than per-mutant, accepted.** A pass-through that later grows an
  `if` hides a real gap, and nothing mechanical catches it. The rule that
  such files hold no decisions is the mitigation, enforced by review. A
  checker (no branches in excluded files) is available if review misses
  one; it is not built ahead of that.
- **Triage beads become small refactors.** throwntom-gz9z.1's file beads
  were written with the source read-only and tests as the deliverable.
  Under this decision several of them relocate a line or add a seam before
  writing the test. That is a scope change to those beads, taken here on
  purpose: the alternative is an equivalents file that records what the
  code cannot prove.
- **A fourth equivalents category, rejected.** It would need a superseding
  ADR against ADR-017:119-122, and it rots on contact with the code: the
  `SMAppServiceRegistrar.swift:52` and `ReminderResponder.swift:157`
  entries went stale the day throwntom-ejqc put a seam one level above
  them, and every seam added later would earn its default closure a new
  entry. A scope rule does not accumulate that way.
- **Seams alone, rejected.** A seam does not observe the SDK call; it
  moves it to a one-line default, which the tool mutates like any other
  line. Without a scope rule for where that line lands, seams produce
  exactly the four pending `NSSound.beep()` entries.
- **Excluding `SystemReminderPresenter.swift` whole, rejected.** Five of
  its mutants are real and killed. The split costs one file and keeps them.
- **Bootstrap stays in scope for now.** `AppEnvironment.swift:82`
  (`responder.start()`) is unreachable today for the same reason as
  `ReminderResponder.swift:47` and becomes killable once that line moves;
  the file has tests and a real own-Timeout entry (`AppEnvironment.swift:73`),
  so it is not excluded as Go's `main.go` is. Revisit if it fills with
  wiring nothing can assert on.
- **Not covered here.** `Mascot/MascotView.swift:126:26` and `135:27` are
  observable only through elapsed time or a live accessibility tree; those
  are an injected clock and throwntom-kt39 (XCUITest), not exclusions.
  `WindowElevation.swift:68` (`super.viewDidMoveToWindow()`) is a proven
  equivalent if AppKit documents the default implementation as doing
  nothing, and a citation to that documentation is the entry's reason if
  so; that is a triage finding, not a category.
