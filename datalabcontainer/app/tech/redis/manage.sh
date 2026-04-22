#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

REDIS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${REDIS_SCRIPT_DIR}/../common.sh"

if ! declare -F strip_cr >/dev/null; then
  strip_cr() {
    local value="${1:-}"
    value="${value//$'\r'/}"
    printf '%s' "${value}"
  }
fi

REDIS_BASE="${RUNTIME_ROOT}/redis"
REDIS_DATA_DIR="${REDIS_BASE}/data"
REDIS_LOG_DIR="${REDIS_BASE}/logs"
REDIS_PID_DIR="${REDIS_BASE}/pids"
REDIS_PID_FILE="${REDIS_PID_DIR}/redis.pid"
REDIS_LOG_FILE="${REDIS_LOG_DIR}/redis.log"
REDIS_CONF_FILE="${REDIS_BASE}/redis.conf"

: "${REDIS_PORT:=6379}"
: "${REDIS_PASSWORD:=admin}"
REDIS_PORT="$(strip_cr "${REDIS_PORT}")"
REDIS_PASSWORD="$(strip_cr "${REDIS_PASSWORD}")"

redis::ensure_dirs() {
  mkdir -p "${REDIS_DATA_DIR}" "${REDIS_LOG_DIR}" "${REDIS_PID_DIR}"
  if [[ "$(id -u)" -eq 0 ]]; then
    # On Windows bind mounts chown may be ignored; keep directories writable for datalab.
    chmod 777 "${REDIS_BASE}" "${REDIS_DATA_DIR}" "${REDIS_LOG_DIR}" "${REDIS_PID_DIR}" 2>/dev/null || true
    [[ -f "${REDIS_PID_FILE}" ]] && chmod 666 "${REDIS_PID_FILE}" 2>/dev/null || true
    [[ -f "${REDIS_LOG_FILE}" ]] && chmod 666 "${REDIS_LOG_FILE}" 2>/dev/null || true
    [[ -f "${REDIS_CONF_FILE}" ]] && chmod 666 "${REDIS_CONF_FILE}" 2>/dev/null || true
  fi
}

redis::pid_alive() {
  [[ -f "${REDIS_PID_FILE}" ]] && kill -0 "$(cat "${REDIS_PID_FILE}")" 2>/dev/null
}

redis::cleanup_stale_pid() {
  if [[ -f "${REDIS_PID_FILE}" ]] && ! redis::pid_alive; then
    rm -f "${REDIS_PID_FILE}"
  fi
}

redis::port_open() {
  local host="$1" port="$2"
  REDIS_WAIT_HOST="${host}" REDIS_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["REDIS_WAIT_HOST"]
port = int(os.environ["REDIS_WAIT_PORT"])
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

redis::wait_for_port() {
  local deadline=$((SECONDS + 30))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if redis::port_open localhost "${REDIS_PORT}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

redis::auth_ready() {
  local configured_password
  configured_password="$(redis-cli -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" --no-auth-warning CONFIG GET requirepass 2>/dev/null | awk 'NR==2{print}')"
  [[ "${configured_password}" == "${REDIS_PASSWORD}" ]]
}

redis::write_config() {
  cat > "${REDIS_CONF_FILE}" <<EOF
bind 0.0.0.0
protected-mode no
port ${REDIS_PORT}
dir ${REDIS_DATA_DIR}
appendonly yes
daemonize yes
pidfile ${REDIS_PID_FILE}
logfile ${REDIS_LOG_FILE}
requirepass ${REDIS_PASSWORD}
EOF
}

redis::start() {
  redis::ensure_dirs
  redis::cleanup_stale_pid
  redis::write_config

  if redis::pid_alive && redis::port_open localhost "${REDIS_PORT}"; then
    if redis::auth_ready; then
      echo "[*] Redis already running (PID $(cat "${REDIS_PID_FILE}"))."
      return
    fi
    echo "[*] Redis is running without the configured password; restarting with updated auth settings..."
    redis::stop
    sleep 1
  fi

  if redis::pid_alive && redis::port_open localhost "${REDIS_PORT}"; then
    echo "[*] Redis already running (PID $(cat "${REDIS_PID_FILE}"))."
    return
  fi

  echo "[*] Starting Redis..."
  redis-server "${REDIS_CONF_FILE}"

  if ! redis::wait_for_port; then
    echo "[!] Redis failed to open port ${REDIS_PORT}. Recent log lines:" >&2
    tail -n 40 "${REDIS_LOG_FILE}" >&2 || true
    return 1
  fi

  echo "Redis listening on localhost:${REDIS_PORT} (auth=enabled)"
}

redis::stop() {
  if ! redis::pid_alive && ! redis::port_open localhost "${REDIS_PORT}"; then
    echo "[*] Redis is not running."
    return 0
  fi

  echo "[*] Stopping Redis..."
  redis-cli -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" shutdown nosave >/dev/null 2>&1 || true
  if redis::pid_alive; then
    kill "$(cat "${REDIS_PID_FILE}")" >/dev/null 2>&1 || true
  fi
  rm -f "${REDIS_PID_FILE}"
}
