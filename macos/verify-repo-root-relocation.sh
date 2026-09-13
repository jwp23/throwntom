#!/bin/bash
# Reproduces the swift-mutation-testing sandbox bug (throwntom-t7r1): the tool
# symlinks every unmutated source file, including tests, into a scratch
# directory before compiling. #filePath then captures the scratch location,
# so code that walks up from #filePath with deletingLastPathComponent() lands
# in the scratch tree instead of the real repo root.
#
# This copies macos/Throwntom to a scratch directory and replaces the two
# #filePath-sensitive test files with symlinks back to the real repo, exactly
# as the tool's sandbox would, then runs the tests that depend on locating
# the true repo root (go.mod for DaemonHarness, DESIGN.md for DesignTokensTests).
#
# Usage: macos/verify-repo-root-relocation.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg_dir="$repo_root/macos/Throwntom"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

cp -R "$pkg_dir" "$scratch/Throwntom"
rm -rf "$scratch/Throwntom/.build"

relocated_files=(
  "Tests/ThrowntomClientTests/TestSupport.swift"
  "Tests/ThrowntomUITests/DesignTokensTests.swift"
)
for f in "${relocated_files[@]}"; do
  rm "$scratch/Throwntom/$f"
  ln -s "$pkg_dir/$f" "$scratch/Throwntom/$f"
done

cd "$scratch/Throwntom"
swift test --filter 'DaemonClientTests|UnixSocketTransportTests|ReminderNotificationAnswerTests|DesignTokensTests'
