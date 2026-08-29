#!/usr/bin/env bash
# Airbnb Swift style over macos/Throwntom, the way airbnb/swift's own tool runs it:
# SwiftFormat with the verbatim airbnb.swiftformat config, then SwiftLint with its
# swiftlint.yml, --strict so a violation fails the run.
#
#   macos/swift-lint.sh          lint only; exit 1 on any violation (pre-commit, CI)
#   macos/swift-lint.sh --fix    rewrite files in place, then lint what autocorrect could not fix
#
# Both tools are pinned by version so CI and a developer machine disagree only when one of
# them drifts; ci.yml installs both releases by checksum. SwiftFormat's per-user cache is
# ignored: it records a file as clean by content and options, and has reported clean for a
# file the same version then flagged in CI.
set -euo pipefail

SWIFTFORMAT_VERSION=0.62.1
SWIFTLINT_VERSION=0.65.1
SWIFT_VERSION=6.3

PKG="$(cd "$(dirname "$0")/Throwntom" && pwd)"
mode=lint
[[ "${1:-}" == "--fix" ]] && mode=fix

require_version() {
  local tool="$1" want="$2" have
  have="$("$tool" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [[ -z "$have" ]]; then
    echo "swift-lint: $tool not installed (want $want): brew install $tool" >&2
    exit 2
  fi
  if [[ "$have" != "$want" ]]; then
    echo "swift-lint: $tool is $have, want $want" >&2
    exit 2
  fi
}

require_version swiftformat "$SWIFTFORMAT_VERSION"
require_version swiftlint "$SWIFTLINT_VERSION"

cd "$PKG"
format_args=(--config .swiftformat --swiftversion "$SWIFT_VERSION" --cache ignore Sources Tests)
lint_args=(--config .swiftlint.yml --strict --quiet Sources Tests)

if [[ "$mode" == fix ]]; then
  swiftformat "${format_args[@]}"
  swiftlint --fix "${lint_args[@]}"
else
  swiftformat --lint "${format_args[@]}"
fi
swiftlint "${lint_args[@]}"
