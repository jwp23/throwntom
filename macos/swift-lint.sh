#!/usr/bin/env bash
# Airbnb Swift style over macos/Throwntom, the way airbnb/swift's own tool runs it:
# SwiftFormat with the verbatim airbnb.swiftformat config, then SwiftLint with its
# swiftlint.yml, --strict so a violation fails the run.
#
#   macos/swift-lint.sh          lint only; exit 1 on any violation (pre-commit, CI)
#   macos/swift-lint.sh --fix    rewrite files in place, then lint what autocorrect could not fix
#
# Both tools are pinned by version so CI and a developer machine disagree only when one of
# them drifts. If the installed binary on PATH is already the pinned version, it's used as
# is. Otherwise this script fetches the pinned release itself, verifies it against the same
# checksum ci.yml uses, and caches it under macos/.swift-lint-cache so the download happens
# once per machine, not once per invocation. SwiftFormat's per-user cache is ignored
# separately: it records a file as clean by content and options, and has reported clean for
# a file the same version then flagged in CI.
set -euo pipefail

SWIFTFORMAT_VERSION=0.62.1
SWIFTLINT_VERSION=0.65.1
SWIFT_VERSION=6.3

SWIFTFORMAT_URL="https://github.com/nicklockwood/SwiftFormat/releases/download/${SWIFTFORMAT_VERSION}/swiftformat.zip"
SWIFTFORMAT_SHA256="7cb1cb1fae04932047c7015441c543848e8e60e1572d808d080e0a1f1661114a"
SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"
SWIFTLINT_SHA256="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"

PKG="$(cd "$(dirname "$0")/Throwntom" && pwd)"
CACHE_DIR="$(cd "$(dirname "$0")" && pwd)/.swift-lint-cache"
mode=lint
[[ "${1:-}" == "--fix" ]] && mode=fix

tool_version() {
  "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true
}

# Downloads $url into a temp dir, verifies it against $sha256, extracts $member from the
# zip, and installs it at $dest. Never installs a binary whose checksum didn't match.
download_tool() {
  local name="$1" version="$2" url="$3" sha256="$4" member="$5" dest="$6"
  echo "swift-lint: fetching $name $version (installed version does not match)" >&2
  local tmp
  tmp="$(mktemp -d)"

  local zip="$tmp/$name.zip"
  if ! curl -fsSL --proto '=https' --tlsv1.2 -o "$zip" "$url"; then
    rm -rf "$tmp"
    echo "swift-lint: failed to download $name from $url" >&2
    exit 2
  fi

  local got
  got="$(shasum -a 256 "$zip" | awk '{print $1}')"
  if [[ "$got" != "$sha256" ]]; then
    rm -rf "$tmp"
    echo "swift-lint: checksum mismatch for $name" >&2
    echo "  want: $sha256" >&2
    echo "  got:  $got" >&2
    exit 2
  fi

  mkdir -p "$CACHE_DIR"
  unzip -q -o "$zip" "$member" -d "$tmp"
  mv "$tmp/$member" "$dest"
  chmod +x "$dest"
  rm -rf "$tmp"
}

# Resolves $name to a binary that reports exactly $want: the one on PATH if it already
# matches, else a cached download, else a fresh checksummed download. Prints the resolved
# binary's path on stdout.
resolve_tool() {
  local name="$1" want="$2" url="$3" sha256="$4" member="$5"

  local on_path
  on_path="$(command -v "$name" 2>/dev/null || true)"
  if [[ -n "$on_path" ]] && [[ "$(tool_version "$on_path")" == "$want" ]]; then
    echo "$on_path"
    return
  fi

  local cached="$CACHE_DIR/$name-$want"
  if [[ -x "$cached" ]] && [[ "$(tool_version "$cached")" == "$want" ]]; then
    echo "$cached"
    return
  fi
  rm -f "$cached"

  download_tool "$name" "$want" "$url" "$sha256" "$member" "$cached"

  if [[ "$(tool_version "$cached")" != "$want" ]]; then
    echo "swift-lint: downloaded $name reports the wrong version" >&2
    exit 2
  fi
  echo "$cached"
}

SWIFTFORMAT_BIN="$(resolve_tool swiftformat "$SWIFTFORMAT_VERSION" "$SWIFTFORMAT_URL" "$SWIFTFORMAT_SHA256" swiftformat)"
SWIFTLINT_BIN="$(resolve_tool swiftlint "$SWIFTLINT_VERSION" "$SWIFTLINT_URL" "$SWIFTLINT_SHA256" swiftlint)"

cd "$PKG"
format_args=(--config .swiftformat --swiftversion "$SWIFT_VERSION" --cache ignore Sources Tests)
lint_args=(--config .swiftlint.yml --strict --quiet Sources Tests)

if [[ "$mode" == fix ]]; then
  "$SWIFTFORMAT_BIN" "${format_args[@]}"
  "$SWIFTLINT_BIN" --fix "${lint_args[@]}"
else
  "$SWIFTFORMAT_BIN" --lint "${format_args[@]}"
fi
"$SWIFTLINT_BIN" "${lint_args[@]}"
