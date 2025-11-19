#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

AIRFLOW_WEB_PID_FILE="${AIRFLOW_PID_DIR}/webserver.pid"
AIRFLOW_SCHED_PID_FILE="${AIRFLOW_PID_DIR}/scheduler.pid"
AIRFLOW_DEFAULT_USERNAME="${AIRFLOW_DEFAULT_USER:-datalab}"
AIRFLOW_DEFAULT_PASSWORD="${AIRFLOW_DEFAULT_PASS:-airflow}"
AIRFLOW_DEFAULT_EMAIL="${AIRFLOW_DEFAULT_EMAIL:-datalab@example.com}"

airflow::ensure_dirs() {
  mkdir -p "${AIRFLOW_PID_DIR}"
}

airflow::init_db() {
  export AIRFLOW__CORE__LOAD_EXAMPLES="${AIRFLOW__CORE__LOAD_EXAMPLES:-False}"
  airflow db init || true
}

airflow::ensure_default_user() {
  if airflow users list --output json 2>/dev/null | grep -q "\"username\": \"${AIRFLOW_DEFAULT_USERNAME}\""; then
    return
  fi

  echo "[*] Creating default Airflow admin user (${AIRFLOW_DEFAULT_USERNAME})."
  airflow users create \
    --username "${AIRFLOW_DEFAULT_USERNAME}" \
    --password "${AIRFLOW_DEFAULT_PASSWORD}" \
    --firstname Data \
    --lastname Lab \
    --role Admin \
    --email "${AIRFLOW_DEFAULT_EMAIL}" >/dev/null
}

airflow::start_webserver() {
  echo "[*] Starting Airflow webserver..."
  airflow webserver -p 8080 > "${AIRFLOW_PID_DIR}/webserver.log" 2>&1 &
  echo $! > "${AIRFLOW_WEB_PID_FILE}"
}

airflow::start_scheduler() {
  echo "[*] Starting Airflow scheduler..."
  airflow scheduler > "${AIRFLOW_PID_DIR}/scheduler.log" 2>&1 &
  echo $! > "${AIRFLOW_SCHED_PID_FILE}"
}

airflow::start() {
  airflow::ensure_dirs
  airflow::init_db
  airflow::ensure_default_user
  airflow::start_webserver
  airflow::start_scheduler
  echo "Airflow webserver: http://localhost:8080"
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
