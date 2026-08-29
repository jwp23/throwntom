#!/bin/bash
# The macOS dev loop in one command: quit the app, stop its launchd agent, build the bundle,
# install it where Spotlight finds it, and open it.
#   macos/install.sh [dest-dir]     default dest-dir: ~/Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$HOME/Applications}"
APP="$DEST/Throwntom.app"
LABEL=com.jwp23.throwntom.daemon
DOMAIN="gui/$(id -u)"

osascript -e 'tell application "Throwntom" to quit' >/dev/null 2>&1 || true
# The re-signed daemon is refused by launchd while the old registration is loaded.
launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true

"$ROOT/macos/build.sh" >/dev/null

mkdir -p "$DEST"
rm -rf "$APP"
ditto "$ROOT/macos/.build/Throwntom.app" "$APP"
open "$APP"
echo "installed and opened $APP"
echo "stop the timer daemon later with: launchctl bootout $DOMAIN/$LABEL"
