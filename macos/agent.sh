#!/bin/bash
# Standalone launchd agent for developing against throwntomd without the app.
#   macos/agent.sh install     write ~/Library/LaunchAgents/<label>.plist and bootstrap it
#   macos/agent.sh uninstall   bootout and remove the plist
#   macos/agent.sh restart     kickstart the agent so it picks up a rebuilt binary
# Uses macos/.build/throwntomd (run macos/build.sh first). Only one throwntomd can hold the
# lock, and the app's own agent now lives in this same directory, so installing this one
# removes that one; open the app again to put it back.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL=com.jwp23.throwntom.dev
APP_LABEL=com.jwp23.throwntom.daemon
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_PLIST="$HOME/Library/LaunchAgents/$APP_LABEL.plist"
BIN="$ROOT/macos/.build/throwntomd"
LOG="$HOME/.config/throwntom/daemon.log"
DOMAIN="gui/$(id -u)"

case "${1:-}" in
  install)
    [[ -x "$BIN" ]] || { echo "missing $BIN; run macos/build.sh first" >&2; exit 1; }
    # Both agents load at login and both would race for the same lock, so this one takes over
    # rather than fighting: whichever daemon lost would sit there failing to bind the socket.
    if [[ -f "$APP_PLIST" ]]; then
      launchctl bootout "$DOMAIN/$APP_LABEL" 2>/dev/null || true
      # A bootout for a job that was not loaded fails, which is fine; one that leaves the job
      # loaded is not. Removing the plist and bootstrapping anyway would leave the app's daemon
      # holding the lock and this one standing down on every spawn, looking installed but dead.
      if launchctl print "$DOMAIN/$APP_LABEL" >/dev/null 2>&1; then
        echo "could not unload $APP_LABEL; quit Throwntom.app and try again" >&2
        exit 1
      fi
      rm -f "$APP_PLIST"
      echo "removed the app's agent ($APP_LABEL); open Throwntom.app to restore it"
    fi
    mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <!-- Revive it when it fails, never when it stops on purpose: a throwntomd that loses the
       single-instance lock exits 0, and restarting it would only lose the same race again. -->
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
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
    echo "removed $LABEL; open Throwntom.app to bring its own agent back"
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
