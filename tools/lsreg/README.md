# lsreg

Report and prune Launch Services registrations for `com.jwp23.throwntom`.

```console
./lsreg list    # every registration for the bundle id, marked live, stale, or unknown
./lsreg prune   # unregister the stale ones, and only those
```

Build with `go build ./tools/lsreg`, or run it directly with `go run ./tools/lsreg list`.
macOS only: it drives the system `lsregister` tool.

## Why this exists

Launch Services keys registrations on the bundle id, so it behaves exactly like the
launch-agent label documented in `docs/development.md`: every worktree that builds
`Throwntom.app` adds another registration for the same bundle id. Deleting the worktree
does not remove the registration, so dead entries accumulate without bound and outlive
the directories they name. macOS is then free to resolve the app through a bundle that is
no longer on disk, and nothing about the symptom points at Launch Services.

This pileup was investigated as the cause of the missing notification icon in throwntom-3ll
and ruled out: cleaning it up did not bring the icon back. It is a dev-loop hazard in its
own right, not an icon fix.

`macos/build.sh` runs `lsreg prune` after it assembles the bundle, so the dev loop heals
itself. Use `lsreg list` when you want to see what is registered. CI runs `build.sh` too,
where `prune` is a harmless no-op on a fresh runner — which also means CI exercises nothing
of this tool beyond its unit tests.

## Safety

`prune` unregisters a path only when both hold:

- the registration's own `identifier:` field is exactly the Throwntom bundle id — a
  record is never selected because some other field (`codeInfoID`, `activityTypes`)
  quotes the same string;
- the path is absolute and `stat` reports that it does not exist.

Every other outcome keeps the registration. A `stat` that fails for any reason other than
absence — a permission error, an I/O error — is not read as absence, so a live bundle is
never unregistered. The bundle id is a constant, not a flag, so no invocation can aim the
tool at another application.

Two limits worth stating plainly. A bundle on an unmounted volume stats as `ENOENT`, which
is indistinguishable from absence, so it would be pruned; the app would re-register on its
next launch. And there is a millisecond window between the `stat` and the `lsregister -u`
in which a path could reappear — the same benign outcome, so neither is worth code.

This tool never runs `lsregister -kill -r -domain local -domain system -domain user`. `-kill`
does not appear in `lsregister -h` at all; it is widely reported to rebuild the whole
machine's Launch Services database, which is far past a dev-loop fix either way. The
narrower system-level option is `lsregister -gc`, documented by `lsregister -h` as
"Garbage collect old data and compact the database". What it keeps or discards beyond that
is undocumented, and this tool does not rely on it.
