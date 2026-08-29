# lsreg

Report and prune Launch Services registrations for `com.jwp23.throwntom`.

```
lsreg list    # every registration for the bundle id, marked live or stale
lsreg prune   # unregister the stale ones, and only those
```

Build with `go build ./tools/lsreg`, or run it directly with `go run ./tools/lsreg list`.
macOS only: it drives the system `lsregister` tool.

## Why this exists

Launch Services keys registrations on the bundle id, so it behaves exactly like the
launch-agent label documented in `docs/development.md`: every worktree that builds
`Throwntom.app` adds another registration for the same bundle id. Deleting the worktree
does not remove the registration, so dead entries accumulate without bound and outlive
the directories they name. macOS is then free to resolve the app — its icon above all —
through a bundle that is no longer on disk, which presents as a wrong or missing icon
rather than as anything that points at Launch Services.

`macos/build.sh` runs `lsreg prune` after it assembles the bundle, so the dev loop heals
itself. Use `lsreg list` when you want to see what is registered.

## Safety

`prune` unregisters a path only when both hold:

- the registration's own `identifier:` field is exactly the Throwntom bundle id — a
  record is never selected because some other field (`codeInfoID`, `activityTypes`)
  quotes the same string;
- the path is absolute and `stat` reports that it does not exist.

Every other outcome keeps the registration. A `stat` that fails for any reason other
than absence — a permission error, an unreachable volume — is not read as absence, so
a live bundle is never unregistered. The bundle id is a constant, not a flag, so no
invocation can aim the tool at another application.

This tool never runs `lsregister -kill -r -domain local -domain system -domain user`.
That rebuilds the whole machine's Launch Services database and is not a dev-loop fix.
