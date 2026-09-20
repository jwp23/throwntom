#!/usr/bin/env bash
#
# mutation-lock.sh — shared concurrent-run guard for local swift-mutation-testing wrappers.
#
# Never run two swift-mutation-testing processes for the same macOS user at once: the tool's
# startup sweep deletes every other live run's sandbox for this macOS user (Foundation's
# temporaryDirectory ignores $TMPDIR, so there is no way to separate two runs), and the run it
# wipes reports its mutants Unviable or dies without a report.
#
# Sourced by mutation-control.sh and mutate-file.sh so both refuse to start a second run against
# each other, not just against a second invocation of themselves.
#
# The lock is a symlink whose target is the holder's pid. `ln -s` is a single atomic syscall
# that sets the target at creation time, so — unlike a directory-plus-separate-pid-file scheme —
# no other process can ever observe the lock as "present but pid not yet readable," and only one
# of any number of simultaneous `ln -s` calls against the same path can succeed.
#
# No automatic reclaim of a dead-pid lock: checking the pid and removing the lock are two
# separate operations, and `rm -f` deletes whatever is at the path *at that moment* — not
# specifically the stale link that was inspected. Two racing processes can each see the same
# dead pid, and whichever removes second deletes the *other's* freshly claimed live lock, not
# the stale one it inspected — letting both through. There is no reclaim shape (including
# `mv`-based, which is atomic but has the identical steal-a-live-lock problem) that avoids this
# without a fixed-fd lock (`flock`), which macOS doesn't ship and which would be a new
# dependency for a small local guard. So a dead-pid lock always refuses; clearing it is a
# manual, deliberate act by whoever notices, never something the script races to do itself.
#
# Fixed, not derived from $TMPDIR: TMPDIR is caller-controlled, so two invocations started
# with different TMPDIR values would each claim a different lock file and both pass the guard.
# The override exists solely so mutation-control-racetest.sh can point at an isolated lock file
# instead of racing against (and clobbering) a real invocation's production lock; nothing else
# should set it.
#
# Reentrant within one process tree: mutate-file.sh claims the lock itself and then runs
# mutation-control.sh as a subprocess of the same invocation, not a second concurrent run. It
# marks the claim by exporting MUTATION_CONTROL_LOCK_HELD, which the child inherits and checks
# before attempting its own claim. Only an explicit export from a prior successful claim sets
# this, so two independent (sibling, not parent/child) invocations never share it and still
# serialize against each other normally. Nothing else should set this.
#
# Usage: source this file, then:
#   mutation_control_acquire_lock [lock_path]   # defaults to $MUTATION_CONTROL_LOCK_PATH or
#                                                # /tmp/mutation-control.lock; exits 1 on refusal
#   trap 'mutation_control_release_lock' EXIT   # release only if this call actually claimed it

mutation_control_acquire_lock() {
  mutation_control_lock_path="${1:-${MUTATION_CONTROL_LOCK_PATH:-/tmp/mutation-control.lock}}"

  if [[ "${MUTATION_CONTROL_LOCK_HELD:-}" == "$mutation_control_lock_path" ]]; then
    mutation_control_lock_owned=0
    return 0
  fi

  if ! ln -s "$$" "$mutation_control_lock_path" 2>/dev/null; then
    local holder_pid
    holder_pid="$(readlink "$mutation_control_lock_path" 2>/dev/null || true)"
    if [[ -n "$holder_pid" ]] && kill -0 "$holder_pid" 2>/dev/null; then
      echo "$(basename "$0"): another run is already in progress (pid $holder_pid); refusing to start" >&2
    else
      echo "$(basename "$0"): stale lock from dead pid ${holder_pid:-unknown} at $mutation_control_lock_path; remove it manually and retry" >&2
    fi
    exit 1
  fi

  mutation_control_lock_owned=1
  export MUTATION_CONTROL_LOCK_HELD="$mutation_control_lock_path"
}

mutation_control_release_lock() {
  if [[ "${mutation_control_lock_owned:-0}" == 1 ]]; then
    rm -f "$mutation_control_lock_path"
  fi
}
