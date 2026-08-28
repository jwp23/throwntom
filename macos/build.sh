#!/bin/bash
# Build Throwntom.app: go build throwntomd, swift build the app, assemble and ad-hoc sign the bundle.
#   macos/build.sh [dest-dir]     default dest-dir: macos/.build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/macos/.build}"
PKG="$ROOT/macos/Throwntom"
APP="$DEST/Throwntom.app"
LABEL=com.jwp23.throwntom.daemon
VERSION="$(git -C "$ROOT" describe --tags --always 2>/dev/null | sed 's/^v//')"
BUILD="$(git -C "$ROOT" rev-list --count HEAD)"

mkdir -p "$DEST"
(cd "$ROOT" && go build -o "$DEST/throwntomd" ./cmd/throwntomd)
swift build -c release --package-path "$PKG"
BIN_DIR="$(swift build -c release --package-path "$PKG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchAgents"
sed "s/__VERSION__/$VERSION/g; s/__BUILD__/$BUILD/g" "$ROOT/macos/bundle/Info.plist" > "$APP/Contents/Info.plist"
cp "$ROOT/macos/bundle/$LABEL.plist" "$APP/Contents/Library/LaunchAgents/"
cp "$BIN_DIR/Throwntom" "$APP/Contents/MacOS/Throwntom"
cp "$DEST/throwntomd" "$APP/Contents/MacOS/throwntomd"

codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/throwntomd"
codesign --force --sign - --timestamp=none "$APP"

echo "built $APP (version $VERSION)"
echo "run:      open \"$APP\""
echo "if the agent was already registered, launchd will refuse the re-signed daemon;"
echo "reload it:  quit the app; launchctl bootout gui/$(id -u)/$LABEL; open \"$APP\""
echo "note: registration is keyed on the bundle id ($LABEL), so it is shared"
echo "across every worktree build of Throwntom.app - whichever build you opened"
echo "last owns the registered agent, regardless of which worktree built it."
