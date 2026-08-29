#!/usr/bin/env bash
# Render every mascot pose offscreen to PNGs (docs/designs/mascot-screenshots by default).
# Usage: tools/mascot-snap.sh [output-dir]   (default: docs/designs/mascot-screenshots)
set -euo pipefail
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
out=${1:-"$root/docs/designs/mascot-screenshots"}
mkdir -p "$out"
(cd "$root/macos/Throwntom" && MASCOT_SNAPSHOT_DIR="$out" swift test --filter MascotSnapshotTests)
echo "wrote $(ls "$out"/*.png | wc -l | tr -d ' ') images to $out"
