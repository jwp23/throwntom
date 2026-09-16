#!/usr/bin/env bash
#
# mutate-file.sh — run swift-mutation-testing over a subset of macos/Throwntom sources.
#
# Triage helper for the weekly Swift mutation survivors (ADR-015/016). Runs the negative
# control first, then mutates only the files whose path under Sources/ matches KEEP_REGEX,
# and gates the report with tools/swiftmutantsgate. The tool's --exclude is a substring match
# on the absolute path, so every other file in the target is excluded with a slash-anchored
# pattern (/ThrowntomUI/Mascot/Arm.swift cannot match LeftArm.swift).
#
# Never run two swift-mutation-testing processes for the same macOS user at once: the tool's
# startup sweep deletes every other live run's sandbox.
#
# Usage:
#   macos/mutate-file.sh <path-to-swift-mutation-testing> <keep-regex> <report.json>
# Example:
#   macos/mutate-file.sh "$TOOL" '/ThrowntomClient/ChunkedDecoder.swift$' /tmp/report.json

set -euo pipefail

usage="usage: macos/mutate-file.sh <tool> <keep-regex> <report.json>"
tool="${1:?$usage}"
keep="${2:?$usage}"
report="${3:?$usage}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
package="$repo_root/macos/Throwntom"

# Claim the concurrent-run guard for this whole invocation, not just for the mutation-control.sh
# step below: the exported claim lets that step recognize it's running inside an invocation that
# already holds the lock and skip re-claiming it, rather than deadlocking against its own parent.
# See macos/mutation-lock.sh for the guard's atomicity guarantees.
# shellcheck disable=SC1091 # dynamic path via $repo_root; file exists at macos/mutation-lock.sh
source "$repo_root/macos/mutation-lock.sh"
mutation_control_acquire_lock
trap 'mutation_control_release_lock' EXIT

"$repo_root/macos/mutation-control.sh" "$tool"

target="$(cd "$package" && find Sources -name '*.swift' | grep -E "$keep" | sed -E 's|^Sources/([^/]+)/.*|\1|' | sort -u)"
if [[ -z "$target" || $(wc -l <<<"$target") -ne 1 ]]; then
  echo "keep-regex must match files in exactly one target under Sources/; matched: [$target]" >&2
  exit 1
fi

excludes=()
while IFS= read -r file; do
  excludes+=(--exclude "/${file#Sources/}")
done < <(cd "$package" && find "Sources/$target" -name '*.swift' | grep -v -E "$keep" | sort)

(
  cd "$package"
  rm -rf .swift-mutation-testing-cache
  "$tool" . --testing-framework xctest --timeout 120 --concurrency 1 \
    --sources-path "Sources/$target" "${excludes[@]}" --output "$report"
)

echo "mutated files:" && jq -r '.files | keys[]' "$report"
(cd "$repo_root" && go run ./tools/swiftmutantsgate -equivalents .swift-mutation-equivalents.json "$report")
