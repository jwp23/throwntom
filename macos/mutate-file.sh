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

"$repo_root/macos/mutation-control.sh" "$tool"

target="$(cd "$package" && find Sources -name '*.swift' | grep -E "$keep" | sed -E 's|^Sources/([^/]+)/.*|\1|' | sort -u || true)"
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
