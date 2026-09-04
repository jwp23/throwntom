#!/usr/bin/env bash
# Ask Throwntom what macOS will do with a reminder: whether notifications are authorized, which
# settings would deliver one without drawing it, and what is delivered right now. Prints JSON.
# Never prints a notification's title or body.
# Usage: tools/notification-report.sh [Throwntom.app]
#   default app: the running Throwntom, else ~/Applications/Throwntom.app, else macos/.build.
# The app's own executable is run because only it is given the app's notification identity; a
# separate binary is answered with a blank record. It writes the report and exits without opening
# the window, connecting to the daemon or touching a delivered notification, so it is safe to run
# while Throwntom is up.
# The running copy is preferred over a build you just made because macOS keeps delivered
# notifications per app bundle on disk: another build of Throwntom answers about the reminders it
# posted itself, which is none of them. The report's runningApp field says which copy answered.
set -euo pipefail
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
app=${1:-}
if [[ -z $app ]]; then
  pid=$(pgrep -x Throwntom | head -1 || true)
  if [[ -n $pid ]]; then
    app=$(ps -p "$pid" -o comm= | sed 's|/Contents/MacOS/Throwntom$||')
  fi
fi
if [[ -z $app ]]; then
  for candidate in "$HOME/Applications/Throwntom.app" "$root/macos/.build/Throwntom.app"; do
    if [[ -d $candidate ]]; then
      app=$candidate
      break
    fi
  done
fi
if [[ -z $app || ! -x "$app/Contents/MacOS/Throwntom" ]]; then
  echo "no Throwntom.app to ask; build one with macos/build.sh or pass its path" >&2
  exit 1
fi
exec "$app/Contents/MacOS/Throwntom" --notification-report
