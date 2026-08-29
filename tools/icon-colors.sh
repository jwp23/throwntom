#!/usr/bin/env bash
# Prints the dominant opaque colours of an image as hex, most common first.
# Used to keep DESIGN.md's icon-* tokens traceable to the actual icon.
# Usage: tools/icon-colors.sh [image] [count]   (needs ImageMagick 7)
set -euo pipefail
image="${1:-macos/bundle/icon/throwntom-icon-1024-masked.png}"
count="${2:-10}"
# Histogram entries look like: "  225887: (243,106,36,254) #F46B25FF srgba(...)".
# Transparent pixels (alpha < 50%) are dropped; the alpha byte is stripped from the hex.
magick "$image" -depth 8 -colors "$count" -format %c histogram:info: \
  | sort -rn \
  | awk '{
      n = split($2, rgba, ",")
      alpha = 255
      if (n == 4) { alpha = rgba[4]; sub(/\)/, "", alpha) }
      if (alpha + 0 < 128) next
      sub(/:$/, "", $1)
      print substr($3, 1, 7), $1
    }'
