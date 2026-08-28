#!/bin/bash
#
# generate-icon.sh — regenerate Throwntom.app's .icns from the source art.
#
# Masks macos/bundle/icon/throwntom-icon-1024.png with Apple's continuous-
# corner squircle (via mask-icon.swift), builds the 16/32/128/256/512 (1x and
# 2x) .iconset ladder with sips, and packs it into an .icns with iconutil.
# The masked master and the .icns are both committed, so macos/build.sh does
# not need to run this script — only re-run it after the source art changes.
#
# Usage:
#   macos/generate-icon.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_DIR="$ROOT/macos/bundle/icon"
SRC="$ICON_DIR/throwntom-icon-1024.png"
MASTER="$ICON_DIR/throwntom-icon-1024-masked.png"
ICONSET="$ICON_DIR/Throwntom.iconset"
ICNS="$ICON_DIR/Throwntom.icns"

swift "$ROOT/macos/mask-icon.swift" "$SRC" "$MASTER"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$ICONSET"

echo "wrote $ICNS"
