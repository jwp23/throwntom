#!/bin/bash
# Build one spike .app variant.
#   build.sh <variant> <sign-mode: adhoc|unsigned> <dest-dir>
# Each variant gets its own bundle id and launchd label so registrations
# from different variants cannot collide in the Background Task Manager.
set -euo pipefail

VARIANT="$1"; SIGN="$2"; DEST="$3"
BUNDLE_ID="com.throwntom.spike.$VARIANT"
LABEL="$BUNDLE_ID.agent"
SRC="$(cd "$(dirname "$0")/src" && pwd)"
APP="$DEST/Spike-$VARIANT.app"
SDK=$(xcrun --sdk macosx --show-sdk-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchAgents"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>SpikeApp</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Spike-$VARIANT</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

cat > "$APP/Contents/Library/LaunchAgents/$LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>BundleProgram</key><string>Contents/MacOS/spike-agent</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
  <key>AssociatedBundleIdentifiers</key><array><string>$BUNDLE_ID</string></array>
</dict>
</plist>
PLIST

xcrun swiftc -sdk "$SDK" -target arm64-apple-macos13.0 -O \
  -o "$APP/Contents/MacOS/SpikeApp" "$SRC/SpikeApp.swift"
xcrun swiftc -sdk "$SDK" -target arm64-apple-macos13.0 -O \
  -o "$APP/Contents/MacOS/spike-agent" "$SRC/spike-agent.swift"

if [ "$SIGN" = adhoc ]; then
  codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/spike-agent"
  codesign --force --sign - --timestamp=none "$APP"
else
  codesign --remove-signature "$APP/Contents/MacOS/SpikeApp" 2>/dev/null || true
  codesign --remove-signature "$APP/Contents/MacOS/spike-agent" 2>/dev/null || true
  codesign --remove-signature "$APP" 2>/dev/null || true
fi

echo "built $APP ($SIGN)"
codesign -dvv "$APP" 2>&1 | sed 's/^/    /' || echo "    (no signature)"
