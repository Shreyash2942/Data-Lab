#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

AIRFLOW_WEB_PID_FILE="${AIRFLOW_PID_DIR}/webserver.pid"
AIRFLOW_SCHED_PID_FILE="${AIRFLOW_PID_DIR}/scheduler.pid"
AIRFLOW_DEFAULT_USERNAME="${AIRFLOW_DEFAULT_USER:-${CONTAINER_NAME:-datalab}}"
AIRFLOW_DEFAULT_PASSWORD="${AIRFLOW_DEFAULT_PASS:-admin}"
AIRFLOW_DEFAULT_EMAIL="${AIRFLOW_DEFAULT_EMAIL:-${AIRFLOW_DEFAULT_USERNAME}@example.com}"
AIRFLOW_WEB_PORT="${AIRFLOW_WEB_PORT:-8080}"

airflow::ensure_dirs() {
  mkdir -p "${AIRFLOW_PID_DIR}"
}

airflow::migrate_db() {
  export AIRFLOW__CORE__LOAD_EXAMPLES="${AIRFLOW__CORE__LOAD_EXAMPLES:-False}"
  airflow db migrate
}

airflow::ensure_default_user() {
  if airflow users list --output json 2>/dev/null | grep -q "\"username\": \"${AIRFLOW_DEFAULT_USERNAME}\""; then
    airflow users reset-password \
      --username "${AIRFLOW_DEFAULT_USERNAME}" \
      --password "${AIRFLOW_DEFAULT_PASSWORD}" >/dev/null 2>&1 || true
  else
    echo "[*] Creating default Airflow admin user (${AIRFLOW_DEFAULT_USERNAME})."
    airflow users create \
      --username "${AIRFLOW_DEFAULT_USERNAME}" \
      --password "${AIRFLOW_DEFAULT_PASSWORD}" \
      --firstname Data \
      --lastname Lab \
      --role Admin \
      --email "${AIRFLOW_DEFAULT_EMAIL}" >/dev/null
  fi
}

airflow::pid_alive() {
  local pid_file="$1"
  [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null
}

airflow::cleanup_stale_pids() {
  if [[ -f "${AIRFLOW_WEB_PID_FILE}" ]] && ! kill -0 "$(cat "${AIRFLOW_WEB_PID_FILE}")" 2>/dev/null; then
    rm -f "${AIRFLOW_WEB_PID_FILE}"
  fi
  if [[ -f "${AIRFLOW_SCHED_PID_FILE}" ]] && ! kill -0 "$(cat "${AIRFLOW_SCHED_PID_FILE}")" 2>/dev/null; then
    rm -f "${AIRFLOW_SCHED_PID_FILE}"
  fi
}

airflow::stop_webserver_pid() {
  if [[ -f "${AIRFLOW_WEB_PID_FILE}" ]]; then
    kill "$(cat "${AIRFLOW_WEB_PID_FILE}")" 2>/dev/null || true
    rm -f "${AIRFLOW_WEB_PID_FILE}"
  fi
}

airflow::port_open() {
  local host="$1" port="$2"
  AIRFLOW_WAIT_HOST="${host}" AIRFLOW_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["AIRFLOW_WAIT_HOST"]
port = int(os.environ["AIRFLOW_WAIT_PORT"])
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

airflow::wait_for_port() {
  local host="$1" port="$2" deadline
  deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if airflow::port_open "${host}" "${port}"; then
      return 0
    fi
    sleep 1
  done
  echo "[!] Airflow webserver did not open ${host}:${port} within 60s." >&2
  return 1
}

airflow::start_webserver() {
  if airflow::pid_alive "${AIRFLOW_WEB_PID_FILE}"; then
    if airflow::port_open localhost "${AIRFLOW_WEB_PORT}"; then
      echo "[*] Airflow webserver already running (PID $(cat "${AIRFLOW_WEB_PID_FILE}"))."
      return
    fi
    echo "[*] Airflow webserver PID present but port ${AIRFLOW_WEB_PORT} is closed; restarting..."
    airflow::stop_webserver_pid
    sleep 1
  fi

  if [[ -f "${AIRFLOW_WEB_PID_FILE}" ]]; then
    rm -f "${AIRFLOW_WEB_PID_FILE}"
  fi

  if airflow::port_open localhost "${AIRFLOW_WEB_PORT}"; then
    echo "[*] Port ${AIRFLOW_WEB_PORT} is already in use; assuming Airflow webserver is healthy."
    return
  fi

  echo "[*] Starting Airflow webserver..."
  airflow webserver --pid "${AIRFLOW_WEB_PID_FILE}" -p "${AIRFLOW_WEB_PORT}" > "${AIRFLOW_PID_DIR}/webserver.log" 2>&1 &
  if ! airflow::wait_for_port localhost "${AIRFLOW_WEB_PORT}"; then
    echo "[!] Airflow webserver failed to bind to port ${AIRFLOW_WEB_PORT}. Recent log lines:" >&2
    tail -n 40 "${AIRFLOW_PID_DIR}/webserver.log" >&2 || true
    exit 1
  fi
}

airflow::start_scheduler() {
  if airflow::pid_alive "${AIRFLOW_SCHED_PID_FILE}"; then
    echo "[*] Airflow scheduler already running (PID $(cat "${AIRFLOW_SCHED_PID_FILE}"))."
    return
  fi
  echo "[*] Starting Airflow scheduler..."
  airflow scheduler --pid "${AIRFLOW_SCHED_PID_FILE}" > "${AIRFLOW_PID_DIR}/scheduler.log" 2>&1 &
}

airflow::start() {
  airflow::ensure_dirs
  airflow::cleanup_stale_pids
  airflow::migrate_db
  airflow::ensure_default_user
  airflow::start_webserver
  airflow::start_scheduler
  echo "Airflow webserver: $(common::ui_url "${AIRFLOW_WEB_PORT}" "/")"
  echo "Airflow login: username=${AIRFLOW_DEFAULT_USERNAME} password=${AIRFLOW_DEFAULT_PASSWORD}"
}

airflow::stop() {
  if [ -f "${AIRFLOW_WEB_PID_FILE}" ]; then
    kill "$(cat "${AIRFLOW_WEB_PID_FILE}")" || true
    rm -f "${AIRFLOW_WEB_PID_FILE}"
  else
    pkill -f "airflow webserver" || true
  fi

  if [ -f "${AIRFLOW_SCHED_PID_FILE}" ]; then
    kill "$(cat "${AIRFLOW_SCHED_PID_FILE}")" || true
    rm -f "${AIRFLOW_SCHED_PID_FILE}"
  else
    pkill -f "airflow scheduler" || true
  fi

  echo "Airflow services stopped."
}
