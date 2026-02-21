#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

POSTGRES_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${POSTGRES_SCRIPT_DIR}/../common.sh"

if ! declare -F strip_cr >/dev/null; then
  strip_cr() {
    local value="${1:-}"
    value="${value//$'\r'/}"
    printf '%s' "${value}"
  }
fi

POSTGRES_BASE="${RUNTIME_ROOT}/postgres"
POSTGRES_DATA_DIR="${POSTGRES_BASE}/data"
POSTGRES_LOG_DIR="${POSTGRES_BASE}/logs"
POSTGRES_PID_DIR="${POSTGRES_BASE}/pids"
POSTGRES_PID_FILE="${POSTGRES_PID_DIR}/postgres.pid"
POSTGRES_LOG_FILE="${POSTGRES_LOG_DIR}/postgres.log"

: "${POSTGRES_PORT:=5432}"
: "${POSTGRES_DB:=datalab}"
: "${POSTGRES_USER:=admin}"
: "${POSTGRES_PASSWORD:=admin}"
: "${POSTGRES_ADMIN_USER:=admin}"
: "${POSTGRES_ADMIN_PASSWORD:=admin}"
: "${POSTGRES_OS_USER:=datalab}"
: "${POSTGRES_SUPERUSER:=${POSTGRES_OS_USER}}"
POSTGRES_PORT="$(strip_cr "${POSTGRES_PORT}")"
POSTGRES_DB="$(strip_cr "${POSTGRES_DB}")"
POSTGRES_USER="$(strip_cr "${POSTGRES_USER}")"
POSTGRES_PASSWORD="$(strip_cr "${POSTGRES_PASSWORD}")"
POSTGRES_ADMIN_USER="$(strip_cr "${POSTGRES_ADMIN_USER}")"
POSTGRES_ADMIN_PASSWORD="$(strip_cr "${POSTGRES_ADMIN_PASSWORD}")"
POSTGRES_OS_USER="$(strip_cr "${POSTGRES_OS_USER}")"
POSTGRES_SUPERUSER="$(strip_cr "${POSTGRES_SUPERUSER}")"

postgres::find_bin() {
  local name="$1"
  if command -v "${name}" >/dev/null 2>&1; then
    command -v "${name}"
    return
  fi

  local candidate
  candidate="$(ls -1 /usr/lib/postgresql/*/bin/"${name}" 2>/dev/null | tail -n 1 || true)"
  if [[ -n "${candidate}" ]]; then
    printf '%s\n' "${candidate}"
    return
  fi

  echo "[!] Could not find PostgreSQL binary: ${name}" >&2
  return 1
}

POSTGRES_INITDB_BIN="$(postgres::find_bin initdb)"
POSTGRES_PG_CTL_BIN="$(postgres::find_bin pg_ctl)"
POSTGRES_PSQL_BIN="$(postgres::find_bin psql)"
POSTGRES_PG_ISREADY_BIN="$(postgres::find_bin pg_isready)"

postgres::ensure_dirs() {
  mkdir -p "${POSTGRES_DATA_DIR}" "${POSTGRES_LOG_DIR}" "${POSTGRES_PID_DIR}" "${POSTGRES_BASE}"
  chown -R "${POSTGRES_OS_USER}:${POSTGRES_OS_USER}" "${POSTGRES_BASE}"
  chmod 700 "${POSTGRES_DATA_DIR}" || true
}

postgres::pid_alive() {
  [[ -f "${POSTGRES_PID_FILE}" ]] && kill -0 "$(cat "${POSTGRES_PID_FILE}")" 2>/dev/null
}

postgres::cleanup_stale_pid() {
  if [[ -f "${POSTGRES_PID_FILE}" ]] && ! postgres::pid_alive; then
    rm -f "${POSTGRES_PID_FILE}"
  fi
}

postgres::port_open() {
  local host="$1" port="$2"
  POSTGRES_WAIT_HOST="${host}" POSTGRES_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["POSTGRES_WAIT_HOST"]
port = int(os.environ["POSTGRES_WAIT_PORT"])
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

postgres::wait_ready() {
  local deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if "${POSTGRES_PG_ISREADY_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -d postgres >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

postgres::as_user() {
  local cmd="$1"
  if [[ "$(id -un)" == "${POSTGRES_OS_USER}" ]]; then
    bash -lc "${cmd}"
    return
  fi
  su -s /bin/bash "${POSTGRES_OS_USER}" -c "${cmd}"
}

postgres::configure_server() {
  local conf="${POSTGRES_DATA_DIR}/postgresql.conf"
  {
    echo ""
    echo "# Data Lab managed settings"
    echo "listen_addresses = '0.0.0.0'"
    echo "port = ${POSTGRES_PORT}"
    echo "unix_socket_directories = '${POSTGRES_BASE}'"
  } >> "${conf}"
}

postgres::configure_hba() {
  local hba="${POSTGRES_DATA_DIR}/pg_hba.conf"
  [[ -f "${hba}" ]] || return 0

  # Allow host-routed clients (pgAdmin container via host.docker.internal).
  if ! grep -qE '^[[:space:]]*host[[:space:]]+all[[:space:]]+all[[:space:]]+0\.0\.0\.0/0[[:space:]]+scram-sha-256([[:space:]]|$)' "${hba}"; then
    {
      echo ""
      echo "# Data Lab managed host access"
      echo "host    all             all             0.0.0.0/0               scram-sha-256"
    } >> "${hba}"
  fi

  if ! grep -qE '^[[:space:]]*host[[:space:]]+all[[:space:]]+all[[:space:]]+::0/0[[:space:]]+scram-sha-256([[:space:]]|$)' "${hba}"; then
    echo "host    all             all             ::0/0                   scram-sha-256" >> "${hba}"
  fi
}

postgres::initdb_if_needed() {
  if [[ -f "${POSTGRES_DATA_DIR}/PG_VERSION" ]]; then
    return
  fi

  if find "${POSTGRES_DATA_DIR}" -mindepth 1 -print -quit 2>/dev/null | grep -q .; then
    local invalid_backup
    invalid_backup="${POSTGRES_BASE}/invalid-data-$(date +%Y%m%d-%H%M%S)"
    echo "[*] Found invalid PostgreSQL data dir (missing PG_VERSION); moving to ${invalid_backup}."
    mkdir -p "${invalid_backup}"
    shopt -s dotglob nullglob
    mv "${POSTGRES_DATA_DIR}"/* "${invalid_backup}/"
    shopt -u dotglob nullglob
  fi

  echo "[*] Initializing PostgreSQL cluster..."
  postgres::as_user "\"${POSTGRES_INITDB_BIN}\" -D \"${POSTGRES_DATA_DIR}\" --encoding=UTF8 --auth-local=trust --auth-host=scram-sha-256 >/dev/null"
  postgres::configure_server
  postgres::configure_hba
}

postgres::safe_ident() {
  [[ "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
}

postgres::bootstrap_user_db() {
  if ! postgres::safe_ident "${POSTGRES_USER}" || ! postgres::safe_ident "${POSTGRES_DB}" || ! postgres::safe_ident "${POSTGRES_ADMIN_USER}"; then
    echo "[!] Skipping DB bootstrap because POSTGRES_USER/POSTGRES_DB/POSTGRES_ADMIN_USER contains unsupported characters." >&2
    return 0
  fi

  local role_exists db_exists escaped_password escaped_admin_password
  escaped_password="${POSTGRES_PASSWORD//\'/\'\'}"
  escaped_admin_password="${POSTGRES_ADMIN_PASSWORD//\'/\'\'}"

  role_exists="$("${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${POSTGRES_USER}'")"
  if [[ "${role_exists}" != "1" ]]; then
    "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -c "SET password_encryption='scram-sha-256'; CREATE ROLE ${POSTGRES_USER} LOGIN PASSWORD '${escaped_password}';" >/dev/null
  else
    "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -c "SET password_encryption='scram-sha-256'; ALTER ROLE ${POSTGRES_USER} WITH PASSWORD '${escaped_password}';" >/dev/null
  fi

  role_exists="$("${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${POSTGRES_ADMIN_USER}'")"
  if [[ "${role_exists}" != "1" ]]; then
    "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -c "SET password_encryption='scram-sha-256'; CREATE ROLE ${POSTGRES_ADMIN_USER} LOGIN PASSWORD '${escaped_admin_password}';" >/dev/null
  else
    "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -c "SET password_encryption='scram-sha-256'; ALTER ROLE ${POSTGRES_ADMIN_USER} WITH PASSWORD '${escaped_admin_password}';" >/dev/null
  fi

  db_exists="$("${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'")"
  if [[ "${db_exists}" != "1" ]]; then
    "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -c "CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};" >/dev/null
  fi

  "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -c "GRANT CONNECT ON DATABASE postgres TO ${POSTGRES_ADMIN_USER};" >/dev/null || true
  "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -c "GRANT CONNECT ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_ADMIN_USER};" >/dev/null || true
  "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_ADMIN_USER};" >/dev/null || true
}

postgres::start() {
  postgres::ensure_dirs
  postgres::cleanup_stale_pid
  postgres::initdb_if_needed
  postgres::configure_hba

  if postgres::pid_alive && postgres::port_open localhost "${POSTGRES_PORT}"; then
    "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d postgres -tAc "SELECT pg_reload_conf();" >/dev/null 2>&1 || true
    postgres::bootstrap_user_db
    echo "[*] PostgreSQL already running (PID $(cat "${POSTGRES_PID_FILE}"))."
    return
  fi

  echo "[*] Starting PostgreSQL..."
  postgres::as_user "\"${POSTGRES_PG_CTL_BIN}\" -D \"${POSTGRES_DATA_DIR}\" -l \"${POSTGRES_LOG_FILE}\" -o \"-p ${POSTGRES_PORT} -h 0.0.0.0 -k ${POSTGRES_BASE} -c external_pid_file=${POSTGRES_PID_FILE}\" start >/dev/null"

  if ! postgres::wait_ready; then
    echo "[!] PostgreSQL failed to become ready. Recent log lines:" >&2
    tail -n 40 "${POSTGRES_LOG_FILE}" >&2 || true
    return 1
  fi

  postgres::bootstrap_user_db
  echo "PostgreSQL listening on localhost:${POSTGRES_PORT} (db=${POSTGRES_DB}, user=${POSTGRES_USER})"
}

postgres::stop() {
  if [[ ! -f "${POSTGRES_DATA_DIR}/PG_VERSION" ]]; then
    echo "[*] PostgreSQL is not initialized."
    return 0
  fi

  echo "[*] Stopping PostgreSQL..."
  postgres::as_user "\"${POSTGRES_PG_CTL_BIN}\" -D \"${POSTGRES_DATA_DIR}\" stop -m fast >/dev/null" || true
  rm -f "${POSTGRES_PID_FILE}"
}
