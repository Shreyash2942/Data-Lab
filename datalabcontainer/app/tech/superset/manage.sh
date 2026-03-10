#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

SUPERSET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SUPERSET_SCRIPT_DIR}/../common.sh"

SUPERSET_BASE="${RUNTIME_ROOT}/superset"
SUPERSET_HOME_DIR="${SUPERSET_BASE}/home"
SUPERSET_LOG_DIR="${SUPERSET_BASE}/logs"
SUPERSET_PID_DIR="${SUPERSET_BASE}/pids"
SUPERSET_DB_DIR="${SUPERSET_BASE}/db"
SUPERSET_CONFIG_FILE="${SUPERSET_BASE}/superset_config.py"
SUPERSET_PID_FILE="${SUPERSET_PID_DIR}/superset.pid"
SUPERSET_LOG_FILE="${SUPERSET_LOG_DIR}/superset.log"
SUPERSET_VENV="${SUPERSET_VENV:-/opt/superset-venv}"
SUPERSET_BIN="${SUPERSET_VENV}/bin/superset"

: "${SUPERSET_PORT:=8090}"
: "${SUPERSET_ADMIN_USERNAME:=admin}"
: "${SUPERSET_ADMIN_PASSWORD:=admin}"
: "${SUPERSET_ADMIN_FIRSTNAME:=Data}"
: "${SUPERSET_ADMIN_LASTNAME:=Lab}"
: "${SUPERSET_ADMIN_EMAIL:=admin@local}"
: "${SUPERSET_SECRET_KEY:=datalab-local-superset-secret-key-change-me}"
: "${SUPERSET_SQLLAB_BACKEND_PERSISTENCE:=True}"
: "${SUPERSET_TRINO_DB_NAME:=}"
: "${SUPERSET_TRINO_ICEBERG_DB_NAME:=Trino Iceberg}"
: "${SUPERSET_TRINO_DELTA_DB_NAME:=Trino Delta}"
: "${SUPERSET_TRINO_HUDI_DB_NAME:=Trino Hudi}"
: "${TRINO_HOST:=localhost}"
: "${TRINO_PORT:=8091}"
: "${TRINO_USER:=trino}"
: "${TRINO_DEFAULT_CATALOG:=iceberg}"
: "${TRINO_DEFAULT_SCHEMA:=default}"

superset::ensure_dirs() {
  mkdir -p "${SUPERSET_BASE}" "${SUPERSET_HOME_DIR}" "${SUPERSET_LOG_DIR}" "${SUPERSET_PID_DIR}" "${SUPERSET_DB_DIR}"
  if [[ "$(id -u)" -eq 0 ]]; then
    local app_user="${LAB_APP_USER:-datalab}"
    chown -R "${app_user}:${app_user}" "${SUPERSET_BASE}" 2>/dev/null || true
    chmod 777 "${SUPERSET_BASE}" "${SUPERSET_HOME_DIR}" "${SUPERSET_LOG_DIR}" "${SUPERSET_PID_DIR}" "${SUPERSET_DB_DIR}" 2>/dev/null || true
  fi
}

superset::pid_alive() {
  [[ -f "${SUPERSET_PID_FILE}" ]] && kill -0 "$(cat "${SUPERSET_PID_FILE}")" 2>/dev/null
}

superset::cleanup_stale_pid() {
  if [[ -f "${SUPERSET_PID_FILE}" ]] && ! superset::pid_alive; then
    rm -f "${SUPERSET_PID_FILE}"
  fi
}

superset::port_open() {
  local host="$1" port="$2"
  SUPERSET_WAIT_HOST="${host}" SUPERSET_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["SUPERSET_WAIT_HOST"]
port = int(os.environ["SUPERSET_WAIT_PORT"])
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

superset::wait_for_port() {
  local host="$1" port="$2" deadline
  deadline=$((SECONDS + 90))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if superset::port_open "${host}" "${port}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

superset::write_config() {
  local db_path="${SUPERSET_DB_DIR}/superset.db"
  cat > "${SUPERSET_CONFIG_FILE}" <<EOF
import os
SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "${SUPERSET_SECRET_KEY}")
SQLALCHEMY_DATABASE_URI = "sqlite:///${db_path}"
WTF_CSRF_ENABLED = True
TALISMAN_ENABLED = False
FEATURE_FLAGS = {
    "SQLLAB_BACKEND_PERSISTENCE": ${SUPERSET_SQLLAB_BACKEND_PERSISTENCE},
}
EOF
}

superset::bootstrap_metadata() {
  env \
    FLASK_APP="superset" \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    "${SUPERSET_BIN}" db upgrade >/dev/null

  env \
    FLASK_APP="superset" \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    "${SUPERSET_BIN}" fab create-admin \
      --username "${SUPERSET_ADMIN_USERNAME}" \
      --firstname "${SUPERSET_ADMIN_FIRSTNAME}" \
      --lastname "${SUPERSET_ADMIN_LASTNAME}" \
      --email "${SUPERSET_ADMIN_EMAIL}" \
      --password "${SUPERSET_ADMIN_PASSWORD}" >/dev/null 2>&1 || true

  env \
    FLASK_APP="superset" \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    "${SUPERSET_BIN}" init >/dev/null
}

superset::ensure_trino_database() {
  if [[ -z "${SUPERSET_TRINO_DB_NAME}" ]]; then
    return 0
  fi
  local trino_uri
  trino_uri="trino://${TRINO_USER}@${TRINO_HOST}:${TRINO_PORT}/${TRINO_DEFAULT_CATALOG}/${TRINO_DEFAULT_SCHEMA}"
  env \
    FLASK_APP="superset" \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    "${SUPERSET_BIN}" set-database-uri \
      -d "${SUPERSET_TRINO_DB_NAME}" \
      -u "${trino_uri}" >/dev/null 2>&1 || true
}

superset::ensure_trino_lakehouse_databases() {
  local iceberg_uri delta_uri hudi_uri
  iceberg_uri="trino://${TRINO_USER}@${TRINO_HOST}:${TRINO_PORT}/iceberg/${TRINO_DEFAULT_SCHEMA}"
  delta_uri="trino://${TRINO_USER}@${TRINO_HOST}:${TRINO_PORT}/delta/${TRINO_DEFAULT_SCHEMA}"
  hudi_uri="trino://${TRINO_USER}@${TRINO_HOST}:${TRINO_PORT}/hudi/${TRINO_DEFAULT_SCHEMA}"

  env \
    FLASK_APP="superset" \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    "${SUPERSET_BIN}" set-database-uri -d "${SUPERSET_TRINO_ICEBERG_DB_NAME}" -u "${iceberg_uri}" >/dev/null 2>&1 || true

  env \
    FLASK_APP="superset" \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    "${SUPERSET_BIN}" set-database-uri -d "${SUPERSET_TRINO_DELTA_DB_NAME}" -u "${delta_uri}" >/dev/null 2>&1 || true

  env \
    FLASK_APP="superset" \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    "${SUPERSET_BIN}" set-database-uri -d "${SUPERSET_TRINO_HUDI_DB_NAME}" -u "${hudi_uri}" >/dev/null 2>&1 || true

  python3 - <<PY
import sqlite3
db_path = "${SUPERSET_DB_DIR}/superset.db"
names = [
    "${SUPERSET_TRINO_ICEBERG_DB_NAME}",
    "${SUPERSET_TRINO_DELTA_DB_NAME}",
    "${SUPERSET_TRINO_HUDI_DB_NAME}",
]
optional = "${SUPERSET_TRINO_DB_NAME}"
if optional:
    names.append(optional)
conn = sqlite3.connect(db_path)
cur = conn.cursor()
for name in names:
    cur.execute("UPDATE dbs SET allow_dml = 1 WHERE database_name = ?", (name,))
conn.commit()
conn.close()
PY
}

superset::start() {
  superset::ensure_dirs
  superset::cleanup_stale_pid
  superset::write_config

  if [[ ! -x "${SUPERSET_BIN}" ]]; then
    echo "[!] Superset binary not found at ${SUPERSET_BIN}; rebuild image." >&2
    return 1
  fi

  if superset::pid_alive && superset::port_open localhost "${SUPERSET_PORT}"; then
    echo "[*] Superset already running (PID $(cat "${SUPERSET_PID_FILE}"))."
    return 0
  fi

  superset::bootstrap_metadata
  superset::ensure_trino_database
  superset::ensure_trino_lakehouse_databases
  pkill -f "${SUPERSET_VENV}/bin/superset run" >/dev/null 2>&1 || true
  echo "[*] Starting Superset on $(common::ui_url "${SUPERSET_PORT}" "/")..."
  env \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    FLASK_APP="superset" \
    nohup "${SUPERSET_BIN}" run -p "${SUPERSET_PORT}" -h 0.0.0.0 \
      > "${SUPERSET_LOG_FILE}" 2>&1 &
  echo $! > "${SUPERSET_PID_FILE}"

  if ! superset::wait_for_port localhost "${SUPERSET_PORT}"; then
    echo "[!] Superset failed to open port ${SUPERSET_PORT}; see ${SUPERSET_LOG_FILE}" >&2
    return 1
  fi
  echo "[+] Superset started (PID $(cat "${SUPERSET_PID_FILE}"))."
}

superset::stop() {
  superset::cleanup_stale_pid
  if superset::pid_alive; then
    kill "$(cat "${SUPERSET_PID_FILE}")" 2>/dev/null || true
  fi
  pkill -f "${SUPERSET_VENV}/bin/superset run" >/dev/null 2>&1 || true
  rm -f "${SUPERSET_PID_FILE}"
  echo "[+] Superset stopped."
}

superset::status() {
  if superset::pid_alive && superset::port_open localhost "${SUPERSET_PORT}"; then
    echo "[+] Superset: $(common::ui_url "${SUPERSET_PORT}" "/")"
  else
    echo "[-] Superset: not running"
  fi
}
