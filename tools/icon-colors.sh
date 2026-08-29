#!/usr/bin/env bash
# Prints the dominant colours of an image as hex, most common first.
# Used to keep DESIGN.md's icon-* tokens traceable to the actual icon.
# Usage: tools/icon-colors.sh [image] [count]   (needs ImageMagick 7)
set -euo pipefail
image="${1:-macos/bundle/icon/throwntom-icon-1024-masked.png}"
count="${2:-10}"
magick "$image" -alpha off -colors "$count" -depth 8 -format %c histogram:info: \
  | sort -rn | awk '{print $3, $1}' | sed 's/:$//'
