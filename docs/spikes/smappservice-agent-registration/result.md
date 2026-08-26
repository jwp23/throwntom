# Spike: SMAppService agent registration from a development build

Bead: throwntom-s9z.7 · Blocks: throwntom-s9z.4 (macOS menu bar app)
Run: 2026-08-25

## Question

The [native macOS client design](../../designs/native-macos-client.md) has
the menu bar app register a launchd agent with
`SMAppService.agent(plistName:)`. Does that call, from an unsigned or
ad-hoc-signed development build:

- prompt the user,
- require the bundle to live in `/Applications`, or
- fail outright?

And does the `SMAppService.mainApp` login-item toggle work under the same
conditions? The answers decide how `build.sh` signs the bundle and how the
app must handle registration failure.

## Verdict

**No prompt, no `/Applications` requirement, no failure.** An ad-hoc
signature is sufficient, and `swiftc` and Xcode already produce one by
default. Step 4 can register the agent straight from the build directory.

## Environment

- macOS 26.5 (build 25F71), Apple Silicon
- Xcode 26.6 (build 17F113)
- `security find-identity -v -p codesigning` → **0 valid identities**, so
  no Developer ID variant could be measured. Only unsigned and ad-hoc.

## Method

`build.sh` assembles a throwaway `LSUIElement` app bundle per variant:

```
Spike-<variant>.app/Contents/
  Info.plist                                   LSUIElement, CFBundleIdentifier
  MacOS/SpikeApp                               driver (src/SpikeApp.swift)
  MacOS/spike-agent                            placeholder (src/spike-agent.swift)
  Library/LaunchAgents/<label>.plist           BundleProgram, RunAtLoad
```

Each variant gets its own bundle identifier and launchd label so
registrations cannot collide in the Background Task Manager. `SpikeApp`
reads `SPIKE_ACTION` from the environment, runs one of
register/unregister/login-on/login-off/status against
`SMAppService.agent(plistName:)` or `SMAppService.mainApp`, and logs the
status before and after. `spike-agent` appends a start line to a log and
sleeps forever, so `launchctl` shows whether launchd actually ran it.

The bundle is assembled directly rather than through an `.xcodeproj`:
hand-authoring a `pbxproj` adds no signal, and manual assembly gives exact
control over the signing states this spike is measuring.

To reproduce:

```sh
mkdir -p ~/spike-smappservice          # log destination used by the binaries
./build.sh adhoc-local adhoc /tmp/spike-build
SPIKE_ACTION=register \
SPIKE_PLIST=com.throwntom.spike.adhoc-local.agent.plist \
  /tmp/spike-build/Spike-adhoc-local.app/Contents/MacOS/SpikeApp
```

## Matrix

| Variant | `register()` | Status after | Prompt | launchd starts agent | After app relaunch |
|---|---|---|---|---|---|
| Ad-hoc, outside `/Applications` | OK | `.enabled` | none (notification only) | yes | `.enabled` |
| Ad-hoc, inside `/Applications` | OK | `.enabled` | none (notification only) | yes | `.enabled` |
| Unsigned, outside `/Applications` | never runs | — | — | — | — |
| Unsigned, inside `/Applications` | never runs | — | — | — | — |

Status never passed through `.requiresApproval` — registration went
straight to `.enabled`.

### Ad-hoc signed, outside `/Applications`

```
pre  agent=notFound mainApp=notFound
agent.register() -> OK
post agent=enabled mainApp=notRegistered
```

launchd ran the agent immediately:

```
$ launchctl print gui/501/com.throwntom.spike.adhoc-local.agent
	state = running
	program identifier = Contents/MacOS/spike-agent (mode: 2)
	parent bundle identifier = com.throwntom.spike.adhoc-local
	managed_by = com.apple.xpc.ServiceManagement
	runs = 1
	pid = 97601
```

`sfltool dumpbtm` shows the item as `[enabled, allowed, notified]` with
`Developer Name: (null)` — "notified" is the non-modal "Background item
added" banner, not a blocking dialog. It appears in System Settings →
General → Login Items with an empty developer name.

### Ad-hoc signed, inside `/Applications`

Identical (`register() -> OK`, `post agent=enabled`, agent running).
**Bundle location does not affect registration.**

### Unsigned

`codesign --remove-signature` on the bundle and both binaries makes the app
die with **exit 137 (SIGKILL)** on exec, so `register()` never runs. This is
the arm64 code-signing rule, not an `SMAppService` rule, and it is moot in
practice: `swiftc` and Xcode ad-hoc sign by default, so producing a truly
unsigned build takes deliberate effort.

## Additional findings

- **Launch path is irrelevant.** Exec'ing the binary directly and launching
  through LaunchServices (`open -n … --env …`) behave identically. No
  Gatekeeper prompt for a locally built, unquarantined bundle.
- **`register()` is idempotent.** Calling it on an already-`.enabled`
  service succeeds silently.
- **`unregister()` is clean.** Status becomes `.notRegistered` (distinct
  from the `.notFound` seen before a service has ever been registered) and
  the running agent process is terminated.
- **`SMAppService.mainApp` works** under the same conditions:
  `register()` → `.enabled`, `unregister()` → `.notRegistered`.
- **Moving the bundle** while registered leaves the service `.enabled`;
  BTM re-resolves the app by bundle identifier.
- **Rebuilding in place does not restart the agent.** After a rebuild the
  status stays `.enabled` and the *old* process keeps running the deleted
  binary (same pid). Measured later (2026-08-26, throwntom-3pt): launchd pins
  the agent's code signature at registration, so `launchctl kickstart -k`
  on a re-signed binary fails with `OS_REASON_CODESIGNING`, and
  `unregister()`/`register()` from the running app does not refresh it
  either. Unloading the job (`launchctl bootout`) and registering again does.

## Consequences for throwntom-s9z.4

- `build.sh` only needs an ad-hoc signature; no Developer ID, no
  notarization, no `/Applications` install step.
- The app can be registered and run from the build directory.
- The app must still handle `register()` throwing and must read `status`
  rather than assuming success — the user can disable the item in System
  Settings at any time, which yields `.requiresApproval`.
- Any dev iteration needs the bootout-then-register step above.

## Cleanup

The `/Applications` copy was removed, every service unregistered, and
`sfltool dumpbtm` verified to contain zero `throwntom.spike` entries.
