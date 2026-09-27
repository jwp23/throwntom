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
# ADR-017 / fork PR #4 (fix/8jq-1-sandbox-sweep-ownership): the pinned tool's startup sweep
# scopes sandbox removal to ownership, so a second concurrent invocation no longer wipes a
# live run's sandbox. Concurrent invocations of this script no longer need to be serialized.
#
# Usage:
#   macos/mutation-control.sh <path-to-swift-mutation-testing>
#
# Exit status: 0 when both verdicts are as planted; 1 otherwise.

set -euo pipefail

tool="${1:?usage: macos/mutation-control.sh <path-to-swift-mutation-testing>}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

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
