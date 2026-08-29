#!/bin/bash
# Capture the Throwntom window to a PNG without Accessibility permission: find the window
# through CGWindowList, then screencapture it by window number.
#   tools/app-capture.sh [out.png]     default: throwntom-window.png in the current directory
set -euo pipefail

OUT="${1:-throwntom-window.png}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/wid.swift" <<'EOF'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for window in windows where (window[kCGWindowOwnerName as String] as? String) == "Throwntom" {
  print(window[kCGWindowNumber as String] as! Int)
  break
}
EOF
swiftc -O "$WORK/wid.swift" -o "$WORK/wid" 2>/dev/null
WID="$("$WORK/wid")"
[[ -n "$WID" ]] || { echo "no Throwntom window on screen" >&2; exit 1; }
screencapture -x -l "$WID" "$OUT"
echo "captured window $WID to $OUT"
