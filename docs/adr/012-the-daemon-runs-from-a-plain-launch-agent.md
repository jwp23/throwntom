# 12. The daemon runs from a plain launch agent

Date: 2026-09-05

## Status

Accepted.

## Context

The macOS app registered its daemon as a bundled launchd agent through
`SMAppService`, which records it with Background Task Management. Installing
over an existing copy left the agent crash-looping and the window saying
"Timer service isn't answering", with no launchd or System Settings step that
recovered it short of a manual `launchctl bootout`.

Measured on 2026-09-05, the sequence is:

1. the first spawn after the bundle is replaced dies with
   `OS_REASON_CODESIGNING | Launch Constraint Violation (Constraint not matched)`;
2. launchd logs `removing service since it exited with consistent failure` and
   `Requesting LWCR update on next spawn`;
3. the repair fails — `Unable to get updated LWCR for (…, (null), 501), error 0x16`;
4. `KeepAlive` then respawns forever against a record whose bundle no longer
   resolves, giving `copy_bundle_path … error 0x6f` and exit 78 `EX_CONFIG`.

launchd pins a registered agent to a LightWeight Code Requirement derived from
the signature it was registered with. The build signs ad hoc, and an ad-hoc
signature's designated requirement is its cdhash, so **the code identity changes
whenever the code changes**. Every real upgrade therefore fails the constraint.

Two narrower fixes were tried and rejected by measurement:

- **A stable signing identifier.** `codesign --identifier` did make the identity
  stable, and changed nothing: the requirement names the cdhash, not the name.
- **A self-signed certificate.** This does produce a stable designated
  requirement (`identifier … and certificate leaf = H"…"`), but AMFI rejects the
  chain — `"The file is adhoc signed or signed by an unknown certificate chain"`,
  and `Disallowing … because no eligible provisioning profiles found`. Making it
  work would mean each person building the repo installing a trusted code-signing
  root with `sudo`, which is a disproportionate ask and might still not satisfy
  AMFI.

What separates the working case from the broken one is only whether the binary
changed: Go builds are reproducible, so reinstalling an unchanged tree produces
a byte-identical binary whose identity still matches, and the install passes for
a reason unrelated to the code being correct.

A Developer ID would fix this properly — the requirement anchors on the team
identifier, which survives rebuilds — but there is no Apple Developer membership
yet, and the app needs to be upgradable by anyone who clones the repo and runs
the build and install scripts.

## Decision

The daemon runs from a plain launch agent. The app writes
`~/Library/LaunchAgents/com.jwp23.throwntom.daemon.plist` with an **absolute**
`ProgramArguments` path into its own bundle and bootstraps it; on launch it
compares that path against itself and rewrites plus reloads on a mismatch.

There is no Background Task Management record and no launch constraint, so
there is nothing that can go stale when the bundle is replaced.

`KeepAlive` is `{ SuccessfulExit: false }`, not `true`. Only one `throwntomd`
may hold the single-instance lock; the loser exits 0 and stands down, and
reviving it would only lose the same race again.

The app's own login item stays on `SMAppService`. That half never had the
problem: it is a bundle with a stable identifier, and it is what the Login Items
UI is for.

## Consequences

Installing and upgrading leave a working timer service, verified by
`tools/agent-reinstall-check.sh`, which alternates `GOFLAGS` so every pass
installs a genuinely different binary. Four passes in a row pass where the
previous arrangement failed every pass that changed the binary.

The daemon still starts at login: everything in `~/Library/LaunchAgents` is
loaded into the user's session, and the plist sets `RunAtLoad`.

It also still appears in System Settings → General → Login Items, because
Background Task Management tracks plain launch agents too — as a *legacy agent*
named after the app rather than as a registered one
(`registerLaunchItem: … type=legacy agent, disposition=[enabled, allowed…]`).
What changed is who owns the record: launchd resolves the job from the plist's
absolute path, not from a BTM bookmark into the bundle, which is the part that
could not survive the bundle being replaced.

The app's own "open at login" setting is untouched. That is the app itself, not
the agent, and it stays on `SMAppService`.

`macos/agent.sh`'s development job now lives in the same auto-loading directory
as the real agent. Installing it removes the app's agent rather than racing it,
and its `KeepAlive` was changed to match, so a losing daemon stands down instead
of respawning.

**This is an interim decision.** Shipping through the App Store requires
sandboxing, and a sandboxed app cannot write to `~/Library/LaunchAgents`;
`SMAppService` is the sanctioned mechanism there. When a Developer ID is
available, a superseding ADR should move the agent back, at which point the
signature has a stable anchor and the failure above cannot recur.
