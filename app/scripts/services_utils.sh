#!/usr/bin/env bash
# Misc service helpers (currently Airflow).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

services::start_airflow() {
  mkdir -p "${AIRFLOW_PID_DIR}"
  airflow db init || true
  echo "[*] Starting Airflow webserver..."
  airflow webserver -p 8080 > "${AIRFLOW_PID_DIR}/webserver.log" 2>&1 &
  echo $! > "${AIRFLOW_PID_DIR}/webserver.pid"
  echo "[*] Starting Airflow scheduler..."
  airflow scheduler > "${AIRFLOW_PID_DIR}/scheduler.log" 2>&1 &
  echo $! > "${AIRFLOW_PID_DIR}/scheduler.pid"
  echo "Airflow webserver: http://localhost:8080"
}

services::stop_airflow() {
  if [ -f "${AIRFLOW_PID_DIR}/webserver.pid" ]; then
    kill "$(cat "${AIRFLOW_PID_DIR}/webserver.pid}")" || true
    rm -f "${AIRFLOW_PID_DIR}/webserver.pid"
  else
    pkill -f "airflow webserver" || true
  fi
  if [ -f "${AIRFLOW_PID_DIR}/scheduler.pid" ]; then
    kill "$(cat "${AIRFLOW_PID_DIR}/scheduler.pid}")" || true
    rm -f "${AIRFLOW_PID_DIR}/scheduler.pid"
  else
    pkill -f "airflow scheduler" || true
  fi
  echo "Airflow services stopped."
}
