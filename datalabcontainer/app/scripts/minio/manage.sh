#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

MINIO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${MINIO_SCRIPT_DIR}/../common.sh"

MINIO_BASE="${RUNTIME_ROOT}/minio"
MINIO_DATA_DIR="${MINIO_BASE}/data"
MINIO_LOG_DIR="${MINIO_BASE}/logs"
MINIO_PID_DIR="${MINIO_BASE}/pids"

MINIO_API_PORT="${MINIO_API_PORT:-9000}"
MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
MINIO_ROOT_USER="${MINIO_ROOT_USER:-minioadmin}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD:-minioadmin}"

MINIO_PID_FILE="${MINIO_PID_DIR}/minio.pid"
MINIO_LOG_FILE="${MINIO_LOG_DIR}/minio.log"

minio::ensure_dirs() {
  mkdir -p "${MINIO_DATA_DIR}" "${MINIO_LOG_DIR}" "${MINIO_PID_DIR}"
  if [[ "$(id -u)" -eq 0 ]]; then
    local app_user="${LAB_APP_USER:-datalab}"
    chown -R "${app_user}:${app_user}" "${MINIO_BASE}" 2>/dev/null || true
    chmod -R u+rwX,go+rX "${MINIO_BASE}" 2>/dev/null || true
  fi
}

minio::pid_alive() {
  [[ -f "${MINIO_PID_FILE}" ]] && kill -0 "$(cat "${MINIO_PID_FILE}")" 2>/dev/null
}

minio::port_open() {
  local host="$1" port="$2"
  DBUI_WAIT_HOST="${host}" DBUI_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["DBUI_WAIT_HOST"]
port = int(os.environ["DBUI_WAIT_PORT"])
s = socket.socket()
s.settimeout(1)
try:
    s.connect((host, port))
except OSError:
    sys.exit(1)
else:
    s.close()
    sys.exit(0)
PY
}

minio::wait_for_port() {
  local host="$1" port="$2" deadline
  deadline=$((SECONDS + 45))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if minio::port_open "${host}" "${port}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

minio::start() {
  minio::ensure_dirs
  if ! command -v minio >/dev/null 2>&1; then
    echo "[!] minio binary not found; rebuild image to include it." >&2
    return 1
  fi

  if minio::pid_alive && minio::port_open localhost "${MINIO_API_PORT}"; then
    echo "[*] MinIO already running (PID $(cat "${MINIO_PID_FILE}"))."
    return 0
  fi

  pkill -f "minio server" >/dev/null 2>&1 || true
  echo "[*] Starting MinIO on $(common::ui_url "${MINIO_API_PORT}" "/") (console: $(common::ui_url "${MINIO_CONSOLE_PORT}" "/"))..."
  env MINIO_ROOT_USER="${MINIO_ROOT_USER}" MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}" \
    nohup minio server "${MINIO_DATA_DIR}" --address ":${MINIO_API_PORT}" --console-address ":${MINIO_CONSOLE_PORT}" \
      > "${MINIO_LOG_FILE}" 2>&1 &
  echo $! > "${MINIO_PID_FILE}"
  if ! minio::wait_for_port localhost "${MINIO_API_PORT}"; then
    echo "[!] MinIO failed to open port ${MINIO_API_PORT}; see ${MINIO_LOG_FILE}" >&2
    return 1
  fi
  echo "[+] MinIO started (PID $(cat "${MINIO_PID_FILE}"))."
}

minio::stop() {
  if minio::pid_alive; then
    kill "$(cat "${MINIO_PID_FILE}")" 2>/dev/null || true
  fi
  pkill -f "minio server" >/dev/null 2>&1 || true
  rm -f "${MINIO_PID_FILE}"
  echo "[+] MinIO stopped."
}

minio::status() {
  if minio::pid_alive && minio::port_open localhost "${MINIO_API_PORT}"; then
    echo "[+] MinIO API: $(common::ui_url "${MINIO_API_PORT}" "/")"
    echo "[+] MinIO Console: $(common::ui_url "${MINIO_CONSOLE_PORT}" "/")"
  else
    echo "[-] MinIO: not running"
  fi
}
