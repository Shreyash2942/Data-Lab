#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

PGADMIN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${PGADMIN_SCRIPT_DIR}/../common.sh"

PGADMIN_BASE="${RUNTIME_ROOT}/pgadmin"
PGADMIN_DATA_DIR="${PGADMIN_BASE}/data"
PGADMIN_LOG_DIR="${PGADMIN_BASE}/logs"
PGADMIN_PID_DIR="${PGADMIN_BASE}/pids"
PGADMIN_PID_FILE="${PGADMIN_PID_DIR}/pgadmin.pid"
PGADMIN_LOG_FILE="${PGADMIN_LOG_DIR}/pgadmin.log"
PGADMIN_CONFIG_FILE="${PGADMIN_BASE}/config_distro.py"
PGADMIN_SERVERS_FILE="${PGADMIN_BASE}/servers.json"
PGADMIN_VENV_DIR="/opt/pgadmin4-venv"
PGADMIN_BIN="${PGADMIN_VENV_DIR}/bin/pgadmin4"
PGADMIN_SETUP_SCRIPT="${PGADMIN_VENV_DIR}/lib/python3.10/site-packages/pgadmin4/setup.py"

: "${PGADMIN_PORT:=8181}"
: "${PGADMIN_EMAIL:=admin@admin.com}"
: "${PGADMIN_PASSWORD:=admin}"

pgadmin::ensure_dirs() {
  mkdir -p "${PGADMIN_BASE}" "${PGADMIN_DATA_DIR}" "${PGADMIN_LOG_DIR}" "${PGADMIN_PID_DIR}"
  if [[ "$(id -u)" -eq 0 ]]; then
    local app_user="${LAB_APP_USER:-datalab}"
    chown -R "${app_user}:${app_user}" "${PGADMIN_BASE}" 2>/dev/null || true
    chmod 777 "${PGADMIN_BASE}" "${PGADMIN_DATA_DIR}" "${PGADMIN_LOG_DIR}" "${PGADMIN_PID_DIR}" 2>/dev/null || true
  fi
}

pgadmin::pid_alive() {
  [[ -f "${PGADMIN_PID_FILE}" ]] && kill -0 "$(cat "${PGADMIN_PID_FILE}")" 2>/dev/null
}

pgadmin::cleanup_stale_pid() {
  if [[ -f "${PGADMIN_PID_FILE}" ]] && ! pgadmin::pid_alive; then
    rm -f "${PGADMIN_PID_FILE}"
  fi
}

pgadmin::port_open() {
  local host="$1" port="$2"
  PGADMIN_WAIT_HOST="${host}" PGADMIN_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["PGADMIN_WAIT_HOST"]
port = int(os.environ["PGADMIN_WAIT_PORT"])
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

pgadmin::wait_for_port() {
  local host="$1" port="$2" deadline
  deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if pgadmin::port_open "${host}" "${port}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

pgadmin::write_config() {
  cat > "${PGADMIN_CONFIG_FILE}" <<EOF
import os
DATA_DIR = r"${PGADMIN_DATA_DIR}"
LOG_FILE = os.path.join(DATA_DIR, "pgadmin4.log")
SQLITE_PATH = os.path.join(DATA_DIR, "pgadmin4.db")
SESSION_DB_PATH = os.path.join(DATA_DIR, "sessions")
DEFAULT_SERVER = "0.0.0.0"
DEFAULT_SERVER_PORT = ${PGADMIN_PORT}
EOF
}

pgadmin::write_servers_json() {
  local postgres_port="${POSTGRES_PORT:-5432}"
  local postgres_user="${POSTGRES_USER:-admin}"
  local server_label="${CONTAINER_NAME:-datalab}"
  cat > "${PGADMIN_SERVERS_FILE}" <<EOF
{
  "Servers": {
    "1": {
      "Name": "${server_label}",
      "Group": "Servers",
      "Host": "localhost",
      "Port": ${postgres_port},
      "MaintenanceDB": "postgres",
      "Username": "${postgres_user}",
      "SSLMode": "prefer"
    }
  }
}
EOF
}

pgadmin::load_servers() {
  local setup_cmd="${PGADMIN_SETUP_SCRIPT}"
  if [[ ! -f "${setup_cmd}" ]]; then
    setup_cmd="/usr/local/lib/python3.10/dist-packages/pgadmin4/setup.py"
  fi

  if [[ ! -f "${setup_cmd}" ]]; then
    return 0
  fi
  python3 "${setup_cmd}" load-servers "${PGADMIN_SERVERS_FILE}" \
    --user "${PGADMIN_EMAIL}" \
    --replace >/dev/null 2>&1 || true
}

pgadmin::start() {
  pgadmin::ensure_dirs
  pgadmin::cleanup_stale_pid
  pgadmin::write_config
  pgadmin::write_servers_json

  if [[ ! -x "${PGADMIN_BIN}" ]]; then
    PGADMIN_BIN="$(command -v pgadmin4 || true)"
  fi

  if [[ -z "${PGADMIN_BIN}" ]]; then
    echo "[!] pgadmin4 is not installed; cannot start pgAdmin UI." >&2
    return 1
  fi

  if pgadmin::pid_alive && pgadmin::port_open localhost "${PGADMIN_PORT}"; then
    echo "[*] pgAdmin already running (PID $(cat "${PGADMIN_PID_FILE}"))."
    return 0
  fi

  echo "[*] Starting pgAdmin on $(common::ui_url "${PGADMIN_PORT}" "/")..."
  env \
    CONFIG_DISTRO_FILE_PATH="${PGADMIN_CONFIG_FILE}" \
    PGADMIN_SETUP_EMAIL="${PGADMIN_EMAIL}" \
    PGADMIN_SETUP_PASSWORD="${PGADMIN_PASSWORD}" \
    nohup "${PGADMIN_BIN}" > "${PGADMIN_LOG_FILE}" 2>&1 &
  echo $! > "${PGADMIN_PID_FILE}"

  if ! pgadmin::wait_for_port localhost "${PGADMIN_PORT}"; then
    echo "[!] pgAdmin failed to open port ${PGADMIN_PORT}; see ${PGADMIN_LOG_FILE}" >&2
    return 1
  fi

  pgadmin::load_servers
  echo "[+] pgAdmin started (PID $(cat "${PGADMIN_PID_FILE}"))."
}

pgadmin::stop() {
  pgadmin::cleanup_stale_pid
  if pgadmin::pid_alive; then
    kill "$(cat "${PGADMIN_PID_FILE}")" 2>/dev/null || true
  fi
  pkill -f "${PGADMIN_VENV_DIR}/bin/pgadmin4" >/dev/null 2>&1 || true
  pkill -f "/usr/local/bin/pgadmin4" >/dev/null 2>&1 || true
  rm -f "${PGADMIN_PID_FILE}"
  echo "[+] pgAdmin stopped."
}
