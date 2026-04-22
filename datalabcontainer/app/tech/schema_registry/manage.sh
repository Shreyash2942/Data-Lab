#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

SCHEMA_REGISTRY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCHEMA_REGISTRY_SCRIPT_DIR}/../common.sh"

if ! declare -F postgres::start >/dev/null 2>&1; then
  source "${SCHEMA_REGISTRY_SCRIPT_DIR}/../postgres/manage.sh"
fi

SCHEMA_REGISTRY_BASE="${RUNTIME_ROOT}/schema-registry"
SCHEMA_REGISTRY_LOG_DIR="${SCHEMA_REGISTRY_BASE}/logs"
SCHEMA_REGISTRY_PID_DIR="${SCHEMA_REGISTRY_BASE}/pids"
SCHEMA_REGISTRY_DATA_DIR="${SCHEMA_REGISTRY_BASE}/data"
SCHEMA_REGISTRY_PID_FILE="${SCHEMA_REGISTRY_PID_DIR}/schema-registry.pid"
SCHEMA_REGISTRY_LOG_FILE="${SCHEMA_REGISTRY_LOG_DIR}/schema-registry.log"

: "${SCHEMA_REGISTRY_PORT:=8085}"
: "${SCHEMA_REGISTRY_HOST:=0.0.0.0}"
: "${SCHEMA_REGISTRY_MANAGEMENT_HOST:=127.0.0.1}"
: "${SCHEMA_REGISTRY_MANAGEMENT_PORT:=9085}"
: "${SCHEMA_REGISTRY_DB:=registrydb}"
: "${SCHEMA_REGISTRY_DB_USER:=${POSTGRES_ADMIN_USER:-admin}}"
: "${SCHEMA_REGISTRY_DB_PASSWORD:=${POSTGRES_ADMIN_PASSWORD:-admin}}"
: "${APICURIO_REGISTRY_HOME:=/opt/apicurio-registry}"
: "${SCHEMA_REGISTRY_JAVA_HOME:=/opt/java/openjdk-21}"

SCHEMA_REGISTRY_PORT="$(strip_cr "${SCHEMA_REGISTRY_PORT}")"
SCHEMA_REGISTRY_HOST="$(strip_cr "${SCHEMA_REGISTRY_HOST}")"
SCHEMA_REGISTRY_MANAGEMENT_HOST="$(strip_cr "${SCHEMA_REGISTRY_MANAGEMENT_HOST}")"
SCHEMA_REGISTRY_MANAGEMENT_PORT="$(strip_cr "${SCHEMA_REGISTRY_MANAGEMENT_PORT}")"
SCHEMA_REGISTRY_DB="$(strip_cr "${SCHEMA_REGISTRY_DB}")"
SCHEMA_REGISTRY_DB_USER="$(strip_cr "${SCHEMA_REGISTRY_DB_USER}")"
SCHEMA_REGISTRY_DB_PASSWORD="$(strip_cr "${SCHEMA_REGISTRY_DB_PASSWORD}")"
APICURIO_REGISTRY_HOME="$(strip_cr "${APICURIO_REGISTRY_HOME}")"
SCHEMA_REGISTRY_JAVA_HOME="$(strip_cr "${SCHEMA_REGISTRY_JAVA_HOME}")"

schema_registry::ensure_dirs() {
  mkdir -p "${SCHEMA_REGISTRY_LOG_DIR}" "${SCHEMA_REGISTRY_PID_DIR}" "${SCHEMA_REGISTRY_DATA_DIR}"
}

schema_registry::pid_alive() {
  [[ -f "${SCHEMA_REGISTRY_PID_FILE}" ]] && kill -0 "$(cat "${SCHEMA_REGISTRY_PID_FILE}")" 2>/dev/null
}

schema_registry::cleanup_stale_pid() {
  if [[ -f "${SCHEMA_REGISTRY_PID_FILE}" ]] && ! schema_registry::pid_alive; then
    rm -f "${SCHEMA_REGISTRY_PID_FILE}"
  fi
}

schema_registry::port_open() {
  local host="$1" port="$2"
  SCHEMA_REGISTRY_WAIT_HOST="${host}" SCHEMA_REGISTRY_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["SCHEMA_REGISTRY_WAIT_HOST"]
port = int(os.environ["SCHEMA_REGISTRY_WAIT_PORT"])
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

schema_registry::health_ready() {
  curl -fsS "http://127.0.0.1:${SCHEMA_REGISTRY_PORT}/apis/registry/v3/system/info" >/dev/null 2>&1
}

schema_registry::wait_ready() {
  local deadline=$((SECONDS + 90))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if schema_registry::health_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

schema_registry::kill_pid_on_port() {
  local port="$1"
  local pids=""
  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -t -iTCP:${port} -sTCP:LISTEN 2>/dev/null | tr '\n' ' ' || true)"
  elif command -v fuser >/dev/null 2>&1; then
    pids="$(fuser -n tcp "${port}" 2>/dev/null | tr ' ' '\n' | tr '\n' ' ' || true)"
  fi
  if [[ -n "${pids// }" ]]; then
    echo "[!] Schema Registry port ${port} is occupied by PID(s): ${pids}. Killing stale listener(s)..."
    # shellcheck disable=SC2086
    kill ${pids} 2>/dev/null || true
    sleep 1
  fi
}

schema_registry::ensure_database() {
  postgres::start
  postgres::ensure_database "${SCHEMA_REGISTRY_DB}" "${SCHEMA_REGISTRY_DB_USER}"
}

schema_registry::start() {
  schema_registry::ensure_dirs
  schema_registry::cleanup_stale_pid
  schema_registry::ensure_database

  if schema_registry::pid_alive && schema_registry::port_open localhost "${SCHEMA_REGISTRY_PORT}" && schema_registry::health_ready; then
    echo "[*] Schema Registry already running (PID $(cat "${SCHEMA_REGISTRY_PID_FILE}"))."
    return
  fi

  if schema_registry::port_open localhost "${SCHEMA_REGISTRY_PORT}"; then
    if schema_registry::health_ready; then
      echo "[*] Schema Registry already reachable on ${SCHEMA_REGISTRY_PORT}."
      return
    fi
    schema_registry::kill_pid_on_port "${SCHEMA_REGISTRY_PORT}"
    if schema_registry::port_open localhost "${SCHEMA_REGISTRY_PORT}"; then
      echo "[!] Schema Registry port ${SCHEMA_REGISTRY_PORT} is in use by an unhealthy listener and could not be cleared." >&2
      return 1
    fi
  fi

  echo "[*] Starting Schema Registry on http://localhost:${SCHEMA_REGISTRY_PORT}/..."
  (
    cd "${APICURIO_REGISTRY_HOME}/quarkus-app"
    export JAVA_HOME="${SCHEMA_REGISTRY_JAVA_HOME}"
    export PATH="${JAVA_HOME}/bin:${PATH}"
    JAVA_DATA_DIR="${SCHEMA_REGISTRY_DATA_DIR}" \
    APICURIO_STORAGE_KIND="sql" \
    APICURIO_STORAGE_SQL_KIND="postgresql" \
    APICURIO_SQL_INIT="true" \
    APICURIO_DATASOURCE_URL="jdbc:postgresql://127.0.0.1:${POSTGRES_PORT}/${SCHEMA_REGISTRY_DB}" \
    APICURIO_DATASOURCE_USERNAME="${SCHEMA_REGISTRY_DB_USER}" \
    APICURIO_DATASOURCE_PASSWORD="${SCHEMA_REGISTRY_DB_PASSWORD}" \
    nohup java \
      -Djava.util.logging.manager=org.jboss.logmanager.LogManager \
      "-Dquarkus.http.host=${SCHEMA_REGISTRY_HOST}" \
      "-Dquarkus.http.port=${SCHEMA_REGISTRY_PORT}" \
      "-Dquarkus.management.host=${SCHEMA_REGISTRY_MANAGEMENT_HOST}" \
      "-Dquarkus.management.port=${SCHEMA_REGISTRY_MANAGEMENT_PORT}" \
      -jar quarkus-run.jar > "${SCHEMA_REGISTRY_LOG_FILE}" 2>&1 &
    echo $! > "${SCHEMA_REGISTRY_PID_FILE}"
  )

  if ! schema_registry::wait_ready; then
    echo "[!] Schema Registry failed to become ready. Recent log lines:" >&2
    tail -n 80 "${SCHEMA_REGISTRY_LOG_FILE}" >&2 || true
    return 1
  fi

  echo "Schema Registry API: $(common::ui_url "${SCHEMA_REGISTRY_PORT}" "/apis/registry/v3")"
}

schema_registry::stop() {
  if schema_registry::pid_alive; then
    echo "[*] Stopping Schema Registry..."
    kill "$(cat "${SCHEMA_REGISTRY_PID_FILE}")" 2>/dev/null || true
    rm -f "${SCHEMA_REGISTRY_PID_FILE}"
    sleep 1
  else
    rm -f "${SCHEMA_REGISTRY_PID_FILE}"
  fi
}

schema_registry::status() {
  local ok=0
  if schema_registry::port_open localhost "${SCHEMA_REGISTRY_PORT}"; then
    echo "[+] Schema Registry port ${SCHEMA_REGISTRY_PORT} is listening."
  else
    echo "[-] Schema Registry port ${SCHEMA_REGISTRY_PORT} is not listening."
    ok=1
  fi

  if schema_registry::health_ready; then
    echo "[+] Schema Registry health endpoint is ready."
  else
    echo "[-] Schema Registry health endpoint is not ready."
    ok=1
  fi
  return "${ok}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-start}"
  case "${cmd}" in
    start)
      schema_registry::start
      ;;
    stop)
      schema_registry::stop
      ;;
    restart)
      schema_registry::stop || true
      sleep 1
      schema_registry::start
      ;;
    status)
      schema_registry::status
      ;;
    *)
      echo "Usage: $0 {start|stop|restart|status}" >&2
      exit 2
      ;;
  esac
fi
