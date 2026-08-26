#!/bin/bash
# Standalone launchd agent for developing against throwntomd without the app.
#   macos/agent.sh install     write ~/Library/LaunchAgents/<label>.plist and bootstrap it
#   macos/agent.sh uninstall   bootout and remove the plist
#   macos/agent.sh restart     kickstart the agent so it picks up a rebuilt binary
# Uses macos/.build/throwntomd (run macos/build.sh first). Uninstall this before
# registering the app's own agent: only one throwntomd can hold the lock.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL=com.jwp23.throwntom.dev
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$ROOT/macos/.build/throwntomd"
LOG="$HOME/.config/throwntom/daemon.log"
DOMAIN="gui/$(id -u)"

case "${1:-}" in
  install)
    [ -x "$BIN" ] || { echo "missing $BIN; run macos/build.sh first" >&2; exit 1; }
    mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "installed $LABEL (log: $LOG)"
    ;;
  uninstall)
    launchctl bootout "$DOMAIN" "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "removed $LABEL"
    ;;
  restart)
    launchctl kickstart -k "$DOMAIN/$LABEL"
    echo "restarted $LABEL"
    ;;
  *)
    echo "usage: $0 {install|uninstall|restart}" >&2
    exit 2
    ;;
esac
