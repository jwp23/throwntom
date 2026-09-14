#!/usr/bin/env bash
#
# mutation-control.sh — prove swift-mutation-testing reports honestly before trusting a score.
#
# ADR-015's negative control. The tool counts any failing suite as a kill (upstream #66), so a
# suite that breaks inside its sandbox reports a perfect score. This plants a fixture with one
# known survivor into a scratch copy of the whole repo (the daemon tests `go build` from the repo
# root), mutates only that fixture while running the full test suite, and fails unless
# `>` → `>=` is reported Survived and `>` → `<` Killed. The Killed half proves the tests ran.
#
# Never run this while another swift-mutation-testing run is in progress for the same macOS
# user. At startup the tool deletes every sandbox in the per-user temp directory, live or not
# (Foundation's temporaryDirectory ignores $TMPDIR, so there is no way to separate two runs), and
# the run it wipes reports its mutants Unviable or dies without a report.
#
# Usage:
#   macos/mutation-control.sh <path-to-swift-mutation-testing>
#
# Exit status: 0 when both verdicts are as planted; 1 otherwise.

set -euo pipefail

tool="${1:?usage: macos/mutation-control.sh <path-to-swift-mutation-testing>}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# Guard against two mutation-control.sh invocations racing each other: the tool's startup
# sweep wipes every other live run's sandbox for this macOS user (see header comment above),
# so a second invocation must refuse before it ever launches the tool. Scoped to this script's
# own invocations only — swift-mutation-testing has no other checked-in local entry point.
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
# Fixed, not derived from $TMPDIR: TMPDIR is caller-controlled, so two invocations started
# with different TMPDIR values would each claim a different lock file and both pass the guard.
# The override exists solely so mutation-control-racetest.sh can point at an isolated lock file
# instead of racing against (and clobbering) a real invocation's production lock; nothing else
# should set it.
lock_path="${MUTATION_CONTROL_LOCK_PATH:-/tmp/mutation-control.lock}"
if ! ln -s "$$" "$lock_path" 2>/dev/null; then
  holder_pid="$(readlink "$lock_path" 2>/dev/null || true)"
  if [[ -n "$holder_pid" ]] && kill -0 "$holder_pid" 2>/dev/null; then
    echo "mutation-control.sh: another run is already in progress (pid $holder_pid); refusing to start" >&2
  else
    echo "mutation-control.sh: stale lock from dead pid ${holder_pid:-unknown} at $lock_path; remove it manually and retry" >&2
  fi
  exit 1
fi
trap 'rm -f "$lock_path"' EXIT

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"; rm -f "$lock_path"' EXIT

rsync -a --exclude .git --exclude .build --exclude .claude --exclude .beads \
  --exclude .swift-mutation-testing-cache "$repo_root/" "$scratch/repo/"

package="$scratch/repo/macos/Throwntom"
mkdir -p "$package/Sources/ThrowntomClient/MutationControl"
cp "$repo_root/macos/mutation-control/MutationControl.swift" "$package/Sources/ThrowntomClient/MutationControl/"
cp "$repo_root/macos/mutation-control/MutationControlTests.swift" "$package/Tests/ThrowntomClientTests/"

(
  cd "$package"
  "$tool" . --testing-framework xctest --timeout 120 --concurrency 1 \
    --sources-path Sources/ThrowntomClient/MutationControl --output "$scratch/report.json"
)

verdict() {
  local replacement="$1"
  jq -r --arg replacement "$replacement" \
    '[.files[].mutants[] | select(.originalText == ">" and .replacement == $replacement) | .status] | join(",")' \
    "$scratch/report.json"
}

survived="$(verdict ">=")"
killed="$(verdict "<")"
echo "negative control: '>' -> '>=' reported [$survived] (want Survived); '>' -> '<' reported [$killed] (want Killed)"

if [[ "$survived" != "Survived" || "$killed" != "Killed" ]]; then
  echo "negative control failed: mutation verdicts cannot be trusted; no score is filed" >&2
  exit 1
fi
