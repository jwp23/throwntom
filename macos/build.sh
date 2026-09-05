#!/bin/bash
# Build Throwntom.app: go build throwntomd, swift build the app, assemble and ad-hoc sign the bundle.
#   macos/build.sh [dest-dir]     default dest-dir: macos/.build
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/macos/.build}"
PKG="$ROOT/macos/Throwntom"
APP="$DEST/Throwntom.app"
BUNDLE_ID=com.jwp23.throwntom
LABEL="$BUNDLE_ID.daemon"
VERSION="$(git -C "$ROOT" describe --tags --always 2>/dev/null | sed 's/^v//')"
BUILD="$(git -C "$ROOT" rev-list --count HEAD)"

mkdir -p "$DEST"
(cd "$ROOT" && go build -o "$DEST/throwntomd" ./cmd/throwntomd)
swift build -c release --package-path "$PKG"
BIN_DIR="$(swift build -c release --package-path "$PKG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
sed "s/__VERSION__/$VERSION/g; s/__BUILD__/$BUILD/g" "$ROOT/macos/bundle/Info.plist" > "$APP/Contents/Info.plist"
cp "$ROOT/macos/bundle/icon/Throwntom.icns" "$APP/Contents/Resources/Throwntom.icns"
cp "$BIN_DIR/Throwntom" "$APP/Contents/MacOS/Throwntom"
cp "$DEST/throwntomd" "$APP/Contents/MacOS/throwntomd"

codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/throwntomd"
codesign --force --sign - --timestamp=none "$APP"

# Every worktree build adds a Launch Services registration for the shared bundle id,
# and deleting the worktree leaves it behind. Drop the ones whose bundle is gone.
# Runs after assembly so this build's own bundle is on disk and never looks stale.
(cd "$ROOT" && go run ./tools/lsreg prune) ||
  echo "warning: could not prune stale Launch Services registrations (see above)" >&2

echo "built $APP (version $VERSION)"
echo "run:      open \"$APP\""
echo "note: the agent is keyed on the launch-agent label ($LABEL), so it is"
echo "shared across every worktree build of Throwntom.app - whichever build you opened"
echo "last owns the registered agent, regardless of which worktree built it."
echo "Launch Services is keyed the same way, on the bundle id ($BUNDLE_ID), and is worse"
echo "in one respect: deleting a worktree leaves its registration behind, so dead entries"
echo "accumulate and macOS may resolve the app through a build you did not open. This"
echo "script drops registrations whose bundle is gone; see the rest with: go run ./tools/lsreg list"
