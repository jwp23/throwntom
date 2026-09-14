#!/usr/bin/env bash
#
# mutation-control-racetest.sh — regression test for mutation-control.sh's concurrency guard.
#
# Two atomicity bugs have already been found and fixed in this guard's ~20 lines (a
# mkdir-then-write-pid TOCTOU, then a readlink-then-rm-f TOCTOU in the reclaim path this
# script's fix removed entirely). Both were the kind of bug a green test suite doesn't catch
# and a human doesn't reliably catch by eye — they only show up under genuine concurrency.
# This launches many truly simultaneous invocations of mutation-control.sh (backgrounded with
# `&`, no stagger) against a fast stub tool instead of the real swift-mutation-testing binary,
# so it never risks two real mutation runs colliding, and asserts exactly one winner — once
# against a clean start, once against a pre-seeded lock from a dead pid.
#
# Usage:
#   macos/mutation-control-racetest.sh [N]     # N simultaneous racers per scenario, default 10
#
# Exit status: 0 when both scenarios show exactly one winner; 1 otherwise.

set -euo pipefail

n="${1:-10}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
control="$repo_root/macos/mutation-control.sh"
lock_path="${TMPDIR:-/tmp}/mutation-control.lock"

work="$(mktemp -d)"
trap 'rm -rf "$work"; rm -f "$lock_path"' EXIT

# Stands in for swift-mutation-testing: sleeps to hold the lock long enough for racers to
# collide, then writes a report.json in the shape the negative control checks, so a winning
# invocation completes mutation-control.sh end to end rather than failing later for an
# unrelated reason.
stub="$work/stub-tool.sh"
cat >"$stub" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
sleep 2
out=""
while [[ $# -gt 0 ]]; do
  [[ "$1" == "--output" ]] && out="$2"
  shift
done
cat >"$out" <<'JSON'
{"files":[{"path":"MutationControl.swift","mutants":[
  {"originalText":">","replacement":">=","status":"Survived"},
  {"originalText":">","replacement":"<","status":"Killed"}
]}]}
JSON
STUB
chmod +x "$stub"

# Runs $n simultaneous racers, returns the winner count (invocations whose output shows the
# negative control ran to completion, i.e. got past the guard) — matched on the "negative
# control:" line the script only prints after a real run, not on the absence of any specific
# refusal wording (the guard has more than one refusal message and both must count as a loss).
run_race() {
  local logs_dir="$1"
  mkdir -p "$logs_dir"
  local pids=()
  local i
  for ((i = 1; i <= n; i++)); do
    "$control" "$stub" >"$logs_dir/$i.log" 2>&1 &
    pids+=("$!")
  done
  local pid
  for pid in "${pids[@]}"; do
    wait "$pid" || true
  done
  { grep -l "negative control:" "$logs_dir"/*.log 2>/dev/null || true; } | wc -l | tr -d ' '
}

echo "racetest: $n simultaneous invocations, clean start"
clean_logs="$work/clean"
rm -f "$lock_path"
clean_winners="$(run_race "$clean_logs")"
echo "racetest: clean-start winners=$clean_winners (want 1)"

echo "racetest: $n simultaneous invocations, pre-seeded stale (dead-pid) lock"
stale_logs="$work/stale"
rm -f "$lock_path"
ln -s 999999 "$lock_path"
stale_winners="$(run_race "$stale_logs")"
echo "racetest: stale-lock winners=$stale_winners (want 0, since a dead-pid lock always refuses; see mutation-control.sh)"

status=0
if [[ "$clean_winners" != "1" ]]; then
  echo "racetest: FAIL clean-start scenario let $clean_winners racers win (want exactly 1)" >&2
  status=1
fi
if [[ "$stale_winners" != "0" ]]; then
  echo "racetest: FAIL stale-lock scenario let $stale_winners racers win (want 0: a dead-pid lock always refuses, never auto-reclaims)" >&2
  status=1
fi

exit "$status"
