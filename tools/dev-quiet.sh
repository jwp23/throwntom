#!/usr/bin/env bash
#
# dev-quiet.sh — run throwntom against an isolated, silent config.
#
# Sets HOME to a scratch directory for the duration of the run, so the
# process reads and writes its own ~/.config/throwntom (tasks, session,
# events) instead of the real one, and writes a config.toml with
# sound_command set to a no-op so reminders never make noise. Useful for
# manual testing without disturbing a running throwntom or a meeting.
#
# Usage:
#   tools/dev-quiet.sh [throwntom args...]
#
# Runs `go run ./cmd/throwntom` from the repo root; any arguments are
# forwarded to throwntom unchanged (e.g. --config to layer more overrides).

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/.." && pwd)

scratch_home=$(mktemp -d)
trap 'rm -rf -- "${scratch_home}"' EXIT

mkdir -p -- "${scratch_home}/.config/throwntom"
cat >"${scratch_home}/.config/throwntom/config.toml" <<'EOF'
sound_command = ["true"]
EOF

HOME="${scratch_home}" go run "${repo_root}/cmd/throwntom" "$@"
