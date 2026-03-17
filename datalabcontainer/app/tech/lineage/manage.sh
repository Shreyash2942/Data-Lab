#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

LINEAGE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LINEAGE_SCRIPT_DIR}/../common.sh"

if ! declare -F postgres::start >/dev/null 2>&1; then
  source "${LINEAGE_SCRIPT_DIR}/../postgres/manage.sh"
fi
if ! declare -F spark::start >/dev/null 2>&1; then
  source "${LINEAGE_SCRIPT_DIR}/../spark/manage.sh"
fi
if ! declare -F hadoop::ensure_running >/dev/null 2>&1; then
  source "${LINEAGE_SCRIPT_DIR}/../hadoop/manage.sh"
fi

LINEAGE_BASE="${RUNTIME_ROOT}/lineage"
LINEAGE_LOG_DIR="${LINEAGE_BASE}/logs"
LINEAGE_PID_DIR="${LINEAGE_BASE}/pids"
LINEAGE_CONFIG_DIR="${LINEAGE_BASE}/config"
LINEAGE_DEMO_DIR="${LINEAGE_BASE}/demo"
LINEAGE_API_PID_FILE="${LINEAGE_PID_DIR}/marquez-api.pid"
LINEAGE_WEB_PID_FILE="${LINEAGE_PID_DIR}/marquez-web.pid"
LINEAGE_API_LOG_FILE="${LINEAGE_LOG_DIR}/marquez-api.log"
LINEAGE_WEB_LOG_FILE="${LINEAGE_LOG_DIR}/marquez-web.log"
LINEAGE_CONFIG_FILE="${LINEAGE_CONFIG_DIR}/marquez.yml"
LINEAGE_DEMO_SCRIPT="${LINEAGE_SCRIPT_DIR}/demo_pyspark.py"

: "${MARQUEZ_API_PORT:=5000}"
: "${MARQUEZ_ADMIN_PORT:=5001}"
: "${MARQUEZ_WEB_PORT:=3000}"
: "${MARQUEZ_DB:=marquez}"
: "${MARQUEZ_DB_USER:=${POSTGRES_ADMIN_USER:-admin}}"
: "${MARQUEZ_DB_PASSWORD:=${POSTGRES_ADMIN_PASSWORD:-admin}}"
: "${MARQUEZ_HOME:=/opt/marquez}"
: "${MARQUEZ_WEB_HOME:=/opt/marquez-web}"
: "${MARQUEZ_JAVA_HOME:=${JAVA17_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}}"
: "${LINEAGE_NAMESPACE:=datalab}"

MARQUEZ_API_PORT="$(strip_cr "${MARQUEZ_API_PORT}")"
MARQUEZ_ADMIN_PORT="$(strip_cr "${MARQUEZ_ADMIN_PORT}")"
MARQUEZ_WEB_PORT="$(strip_cr "${MARQUEZ_WEB_PORT}")"
MARQUEZ_DB="$(strip_cr "${MARQUEZ_DB}")"
MARQUEZ_DB_USER="$(strip_cr "${MARQUEZ_DB_USER}")"
MARQUEZ_DB_PASSWORD="$(strip_cr "${MARQUEZ_DB_PASSWORD}")"
MARQUEZ_HOME="$(strip_cr "${MARQUEZ_HOME}")"
MARQUEZ_WEB_HOME="$(strip_cr "${MARQUEZ_WEB_HOME}")"
MARQUEZ_JAVA_HOME="$(strip_cr "${MARQUEZ_JAVA_HOME}")"
LINEAGE_NAMESPACE="$(strip_cr "${LINEAGE_NAMESPACE}")"

lineage::ensure_dirs() {
  mkdir -p "${LINEAGE_LOG_DIR}" "${LINEAGE_PID_DIR}" "${LINEAGE_CONFIG_DIR}" "${LINEAGE_DEMO_DIR}"
}

lineage::pid_alive() {
  local pid_file="$1"
  [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null
}

lineage::cleanup_stale_pid() {
  local pid_file="$1"
  if [[ -f "${pid_file}" ]] && ! lineage::pid_alive "${pid_file}"; then
    rm -f "${pid_file}"
  fi
}

lineage::port_open() {
  local host="$1" port="$2"
  LINEAGE_WAIT_HOST="${host}" LINEAGE_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ['LINEAGE_WAIT_HOST']
port = int(os.environ['LINEAGE_WAIT_PORT'])
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

lineage::kill_pid_on_port() {
  local port="$1"
  local pids=""
  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -t -iTCP:${port} -sTCP:LISTEN 2>/dev/null | tr '\n' ' ' || true)"
  elif command -v fuser >/dev/null 2>&1; then
    pids="$(fuser -n tcp "${port}" 2>/dev/null | tr ' ' '\n' | tr '\n' ' ' || true)"
  fi
  if [[ -n "${pids// }" ]]; then
    echo "[!] Port ${port} is occupied by PID(s): ${pids}. Killing stale listener(s)..."
    # shellcheck disable=SC2086
    kill ${pids} 2>/dev/null || true
    sleep 1
  fi
}

lineage::admin_ready() {
  curl -fsS "http://127.0.0.1:${MARQUEZ_ADMIN_PORT}/ping" >/dev/null 2>&1
}

lineage::api_ready() {
  curl -fsS "http://127.0.0.1:${MARQUEZ_API_PORT}/api/v1/namespaces" >/dev/null 2>&1
}

lineage::web_ready() {
  curl -fsS "http://127.0.0.1:${MARQUEZ_WEB_PORT}/healthcheck" >/dev/null 2>&1
}

lineage::wait_api_ready() {
  local deadline=$((SECONDS + 90))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if lineage::admin_ready && lineage::api_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

lineage::wait_web_ready() {
  local deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if lineage::web_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

lineage::render_config() {
  cat > "${LINEAGE_CONFIG_FILE}" <<EOF
server:
  applicationConnectors:
    - type: http
      port: ${MARQUEZ_API_PORT}
      httpCompliance: RFC7230_LEGACY
  adminConnectors:
    - type: http
      port: ${MARQUEZ_ADMIN_PORT}

db:
  driverClass: org.postgresql.Driver
  url: jdbc:postgresql://127.0.0.1:${POSTGRES_PORT:-5432}/${MARQUEZ_DB}
  user: ${MARQUEZ_DB_USER}
  password: ${MARQUEZ_DB_PASSWORD}

migrateOnStartup: true

graphql:
  enabled: true

logging:
  level: INFO
  appenders:
    - type: console

search:
  enabled: false
EOF
}

lineage::resolve_marquez_jar() {
  local jar_path=""
  jar_path="$(find "${MARQUEZ_HOME}" -maxdepth 1 -type f -name 'marquez-*.jar' ! -name '*sources*' ! -name '*javadoc*' | sort | head -n 1)"
  if [[ -z "${jar_path}" ]]; then
    echo "[!] Marquez API jar was not found under ${MARQUEZ_HOME}." >&2
    return 1
  fi
  printf '%s\n' "${jar_path}"
}

lineage::start_api() {
  lineage::ensure_dirs
  lineage::cleanup_stale_pid "${LINEAGE_API_PID_FILE}"
  postgres::start
  postgres::ensure_database "${MARQUEZ_DB}" "${MARQUEZ_DB_USER}"
  lineage::render_config

  if lineage::pid_alive "${LINEAGE_API_PID_FILE}" && lineage::api_ready; then
    echo "[*] Marquez API already running (PID $(cat "${LINEAGE_API_PID_FILE}"))."
    return 0
  fi

  if lineage::port_open localhost "${MARQUEZ_API_PORT}" || lineage::port_open localhost "${MARQUEZ_ADMIN_PORT}"; then
    if lineage::api_ready; then
      echo "[*] Marquez API already reachable on ${MARQUEZ_API_PORT}."
      return 0
    fi
    lineage::kill_pid_on_port "${MARQUEZ_API_PORT}"
    lineage::kill_pid_on_port "${MARQUEZ_ADMIN_PORT}"
  fi

  echo "[*] Starting Marquez API on http://localhost:${MARQUEZ_API_PORT}/..."
  (
    cd "${MARQUEZ_HOME}"
    local jar_path=""
    jar_path="$(lineage::resolve_marquez_jar)"
    export JAVA_HOME="${MARQUEZ_JAVA_HOME}"
    export PATH="${JAVA_HOME}/bin:${PATH}"
    export JAVA_OPTS="${JAVA_OPTS:-} -Duser.timezone=UTC -Dlog4j2.formatMsgNoLookups=true"
    nohup java \
      ${JAVA_OPTS} \
      -jar "${jar_path}" server "${LINEAGE_CONFIG_FILE}" > "${LINEAGE_API_LOG_FILE}" 2>&1 &
    echo $! > "${LINEAGE_API_PID_FILE}"
  )

  if ! lineage::wait_api_ready; then
    echo "[!] Marquez API failed to become ready. Recent log lines:" >&2
    tail -n 80 "${LINEAGE_API_LOG_FILE}" >&2 || true
    return 1
  fi

  echo "Marquez API: $(common::ui_url "${MARQUEZ_API_PORT}" "/api/v1/namespaces")"
}

lineage::start_web() {
  lineage::ensure_dirs
  lineage::cleanup_stale_pid "${LINEAGE_WEB_PID_FILE}"
  if ! lineage::api_ready; then
    lineage::start_api
  fi

  if lineage::pid_alive "${LINEAGE_WEB_PID_FILE}" && lineage::web_ready; then
    echo "[*] Marquez UI already running (PID $(cat "${LINEAGE_WEB_PID_FILE}"))."
    return 0
  fi

  if lineage::port_open localhost "${MARQUEZ_WEB_PORT}"; then
    if lineage::web_ready; then
      echo "[*] Marquez UI already reachable on ${MARQUEZ_WEB_PORT}."
      return 0
    fi
    lineage::kill_pid_on_port "${MARQUEZ_WEB_PORT}"
  fi

  echo "[*] Starting Marquez UI on http://localhost:${MARQUEZ_WEB_PORT}/..."
  (
    cd "${MARQUEZ_WEB_HOME}"
    MARQUEZ_HOST=127.0.0.1 \
    MARQUEZ_PORT=${MARQUEZ_API_PORT} \
    WEB_PORT=${MARQUEZ_WEB_PORT} \
    nohup node setupProxy.js > "${LINEAGE_WEB_LOG_FILE}" 2>&1 &
    echo $! > "${LINEAGE_WEB_PID_FILE}"
  )

  if ! lineage::wait_web_ready; then
    echo "[!] Marquez UI failed to become ready. Recent log lines:" >&2
    tail -n 80 "${LINEAGE_WEB_LOG_FILE}" >&2 || true
    return 1
  fi

  echo "Marquez UI: $(common::ui_url "${MARQUEZ_WEB_PORT}" "/")"
}

lineage::start() {
  lineage::start_api
  lineage::start_web
}

lineage::stop() {
  lineage::cleanup_stale_pid "${LINEAGE_WEB_PID_FILE}"
  if lineage::pid_alive "${LINEAGE_WEB_PID_FILE}"; then
    echo "[*] Stopping Marquez UI..."
    kill "$(cat "${LINEAGE_WEB_PID_FILE}")" 2>/dev/null || true
    rm -f "${LINEAGE_WEB_PID_FILE}"
    sleep 1
  else
    rm -f "${LINEAGE_WEB_PID_FILE}"
  fi
  pkill -f "node setupProxy.js" >/dev/null 2>&1 || true

  lineage::cleanup_stale_pid "${LINEAGE_API_PID_FILE}"
  if lineage::pid_alive "${LINEAGE_API_PID_FILE}"; then
    echo "[*] Stopping Marquez API..."
    kill "$(cat "${LINEAGE_API_PID_FILE}")" 2>/dev/null || true
    rm -f "${LINEAGE_API_PID_FILE}"
    sleep 1
  else
    rm -f "${LINEAGE_API_PID_FILE}"
  fi
  pkill -f "marquez-.*\\.jar server" >/dev/null 2>&1 || true
}

lineage::status() {
  local ok=0
  if lineage::api_ready; then
    echo "[+] Marquez API is ready on port ${MARQUEZ_API_PORT}."
  else
    echo "[-] Marquez API is not ready."
    ok=1
  fi
  if lineage::web_ready; then
    echo "[+] Marquez UI is ready on port ${MARQUEZ_WEB_PORT}."
  else
    echo "[-] Marquez UI is not ready."
    ok=1
  fi
  return "${ok}"
}

lineage::run_spark_demo() {
  local jobs_payload=""
  lineage::start
  hadoop::ensure_running
  spark::ensure_running

  if [[ ! -f "${LINEAGE_DEMO_SCRIPT}" ]]; then
    echo "[!] Spark lineage demo script not found: ${LINEAGE_DEMO_SCRIPT}" >&2
    return 1
  fi

  echo "[*] Running Spark lineage demo..."
  DATALAB_OPENLINEAGE_ENABLED=1 \
  DATALAB_OPENLINEAGE_NAMESPACE="${LINEAGE_NAMESPACE}" \
  bash "${WORKSPACE}/app/bin/spark-submit" \
    --conf "spark.openlineage.namespace=${LINEAGE_NAMESPACE}" \
    "${LINEAGE_DEMO_SCRIPT}"

  sleep 3
  jobs_payload="$(curl -fsS "http://127.0.0.1:${MARQUEZ_API_PORT}/api/v1/namespaces/${LINEAGE_NAMESPACE}/jobs" 2>/dev/null || true)"
  echo "Marquez UI: $(common::ui_url "${MARQUEZ_WEB_PORT}" "/")"
  echo "Marquez API: $(common::ui_url "${MARQUEZ_API_PORT}" "/api/v1/namespaces/${LINEAGE_NAMESPACE}/jobs")"
  if [[ -n "${jobs_payload}" ]] && printf '%s' "${jobs_payload}" | python3 -c 'import json, sys; payload = json.load(sys.stdin); raise SystemExit(0 if payload.get("totalCount", 0) > 0 else 1)'; then
    echo "[+] Marquez recorded Spark lineage for namespace '${LINEAGE_NAMESPACE}'."
  else
    echo "[*] Spark demo completed. If the jobs list is still empty, wait a few seconds and refresh Marquez."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-start}"
  case "${cmd}" in
    start)
      lineage::start
      ;;
    stop)
      lineage::stop
      ;;
    restart)
      lineage::stop || true
      sleep 1
      lineage::start
      ;;
    status)
      lineage::status
      ;;
    run-demo)
      lineage::run_spark_demo
      ;;
    *)
      echo "Usage: $0 {start|stop|restart|status|run-demo}" >&2
      exit 2
      ;;
  esac
fi
