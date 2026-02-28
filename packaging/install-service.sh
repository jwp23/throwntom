#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ "${BINARY_PATH:-}" == "" ]]; then
  if command -v throwntom >/dev/null 2>&1; then
    BINARY_PATH="$(command -v throwntom)"
  else
    BINARY_PATH="${HOME}/.local/bin/throwntom"
  fi
fi

CONFIG_PATH="${CONFIG_PATH:-${HOME}/.config/throwntom/config.toml}"
SOCKET_PATH="${SOCKET_PATH:-${XDG_RUNTIME_DIR:-/tmp}/throwntom.sock}"
LOG_OUT_PATH="${LOG_OUT_PATH:-${HOME}/Library/Logs/throwntom.out.log}"
LOG_ERR_PATH="${LOG_ERR_PATH:-${HOME}/Library/Logs/throwntom.err.log}"

if [[ ! -x "${BINARY_PATH}" ]]; then
  echo "binary not found or not executable: ${BINARY_PATH}" >&2
  exit 1
fi

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

render_template() {
  local src="$1"
  local dst="$2"

  local binary_escaped
  local config_escaped
  local socket_escaped
  local log_out_escaped
  local log_err_escaped
  binary_escaped="$(escape_sed_replacement "${BINARY_PATH}")"
  config_escaped="$(escape_sed_replacement "${CONFIG_PATH}")"
  socket_escaped="$(escape_sed_replacement "${SOCKET_PATH}")"
  log_out_escaped="$(escape_sed_replacement "${LOG_OUT_PATH}")"
  log_err_escaped="$(escape_sed_replacement "${LOG_ERR_PATH}")"

  sed \
    -e "s/@BINARY@/${binary_escaped}/g" \
    -e "s/@CONFIG@/${config_escaped}/g" \
    -e "s/@SOCKET@/${socket_escaped}/g" \
    -e "s/@LOG_OUT@/${log_out_escaped}/g" \
    -e "s/@LOG_ERR@/${log_err_escaped}/g" \
    "${src}" > "${dst}"
}

install_systemd_user_service() {
  local unit_dir="${HOME}/.config/systemd/user"
  local unit_path="${unit_dir}/throwntom.service"
  mkdir -p "${unit_dir}" "$(dirname "${CONFIG_PATH}")"

  render_template "${REPO_ROOT}/packaging/systemd/throwntom.service" "${unit_path}"
  systemctl --user daemon-reload
  systemctl --user enable --now throwntom.service
  echo "installed and started systemd user service: ${unit_path}"
}

install_launchd_agent() {
  local agent_dir="${HOME}/Library/LaunchAgents"
  local label="io.github.jwp23.throwntom"
  local plist_path="${agent_dir}/${label}.plist"
  mkdir -p "${agent_dir}" "$(dirname "${CONFIG_PATH}")" "$(dirname "${LOG_OUT_PATH}")" "$(dirname "${LOG_ERR_PATH}")"

  render_template "${REPO_ROOT}/packaging/launchd/${label}.plist" "${plist_path}"

  if launchctl print "gui/${UID}/${label}" >/dev/null 2>&1; then
    launchctl bootout "gui/${UID}" "${plist_path}" >/dev/null 2>&1 || true
  fi
  launchctl bootstrap "gui/${UID}" "${plist_path}"
  launchctl enable "gui/${UID}/${label}"
  echo "installed and started launchd agent: ${plist_path}"
}

case "$(uname -s)" in
  Linux)
    if ! command -v systemctl >/dev/null 2>&1; then
      echo "systemctl is required on Linux" >&2
      exit 1
    fi
    install_systemd_user_service
    ;;
  Darwin)
    install_launchd_agent
    ;;
  *)
    echo "unsupported platform: $(uname -s)" >&2
    echo "supported platforms: Linux (systemd), macOS (launchd)" >&2
    exit 1
    ;;
esac
