#!/bin/bash
# Check that reinstalling Throwntom leaves a working timer service.
#   tools/agent-reinstall-check.sh [passes]     default passes: 3
#
# Each pass builds a GENUINELY DIFFERENT throwntomd, installs it over the one
# already in ~/Applications, and then asks whether the daemon actually came up.
# The difference matters: Go builds are reproducible, so reinstalling an
# unchanged tree produces a byte-identical binary whose ad-hoc code identity is
# unchanged, launchd's cached launch constraint still matches, and the install
# passes for a reason that has nothing to do with the code being correct. This
# script alternates GOFLAGS so every pass changes the binary, which is what a
# real code change or a user upgrade does.
#
# A failing pass looks like: launchctl status 78 (EX_CONFIG), no throwntomd
# process, no daemon.sock, and the window saying "Timer service isn't answering".
#
# This drives real launchd state for the login session, so it is a local tool,
# not a CI test: it stops and replaces the running daemon.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASSES="${1:-3}"
LABEL=com.jwp23.throwntom.daemon
SOCK="$HOME/.config/throwntom/daemon.sock"
# Long enough for launchd to spawn the daemon and for it to bind the socket;
# a failing job is throttled to a respawn every 10s, so this also gives a
# broken one time to show itself rather than being read while merely slow.
SETTLE=15
failures=0
previous_cdhash=""

# Put the service back in the state a pass is supposed to start from: registered and
# answering. Without this a single broken pass poisons every pass after it, and a fix that
# works looks like a fix that does nothing. The bootout is the known recovery, so it is
# deliberately OUTSIDE the measurement - what is under test is the install that follows.
reset_to_healthy() {
  osascript -e 'tell application "Throwntom" to quit' >/dev/null 2>&1
  sleep 2
  launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1
  sleep 1
  open "$HOME/Applications/Throwntom.app" >/dev/null 2>&1
  sleep "$SETTLE"
  if [[ "$(launchctl list | awk -v l="$LABEL" '$3 == l {print $2}')" == "0" ]]; then
    return 0
  fi
  return 1
}

for pass in $(seq 1 "$PASSES"); do
  # Alternate the flag so consecutive passes never build the same bytes.
  if ((pass % 2 == 0)); then
    export GOFLAGS="-gcflags=all=-l"
  else
    unset GOFLAGS
  fi

  echo "===== pass $pass/$PASSES (GOFLAGS='${GOFLAGS:-}') ====="
  if ! reset_to_healthy; then
    echo "pass $pass: SKIPPED, could not reach a healthy service to install over"
    failures=$((failures + 1))
    continue
  fi
  if ! "$ROOT/macos/install.sh" >/dev/null 2>&1; then
    echo "pass $pass: FAILED to install"
    failures=$((failures + 1))
    continue
  fi
  sleep "$SETTLE"

  status=$(launchctl list | awk -v l="$LABEL" '$3 == l {print $2}')
  runs=$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null | awk '/^[[:space:]]*runs =/ {print $3}')
  http=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
    --unix-socket "$SOCK" http://localhost/v1/tasks 2>/dev/null)
  cdhash=$(codesign -dvvv "$HOME/Applications/Throwntom.app/Contents/MacOS/throwntomd" 2>&1 |
    awk -F= '/^CDHash=/ {print $2}')

  # A pass only means something if this install actually replaced the daemon's code identity.
  # Reinstalling the same bytes leaves launchd's cached launch constraint matching, so the
  # check would go green for a reason that has nothing to do with the fix being present.
  if [[ -n "$previous_cdhash" && "$cdhash" == "$previous_cdhash" ]]; then
    echo "pass $pass: INCONCLUSIVE - daemon CDHash unchanged ($cdhash), nothing was upgraded"
    failures=$((failures + 1))
    previous_cdhash="$cdhash"
    continue
  fi
  previous_cdhash="$cdhash"

  if [[ "$status" == "0" && "$http" == "200" ]]; then
    echo "pass $pass: OK (status=$status runs=$runs http=$http cdhash=${cdhash:0:12})"
  else
    echo "pass $pass: BROKEN (status=$status runs=$runs http=$http cdhash=${cdhash:0:12})"
    failures=$((failures + 1))
  fi
done

echo
if ((failures == 0)); then
  echo "all $PASSES passes left a working timer service"
else
  echo "$failures of $PASSES passes left the timer service down"
  echo "recover with: quit the app; launchctl bootout gui/$(id -u)/$LABEL; open the app"
fi
exit $((failures > 0))
