#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

MONITORING_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${MONITORING_SCRIPT_DIR}/../common.sh"

MONITORING_BASE="${RUNTIME_ROOT}/monitoring"
PROMETHEUS_BASE="${MONITORING_BASE}/prometheus"
GRAFANA_BASE="${MONITORING_BASE}/grafana"
HEALTH_EXPORTER_BASE="${MONITORING_BASE}/health-exporter"
PROMETHEUS_LOG_DIR="${PROMETHEUS_BASE}/logs"
PROMETHEUS_PID_DIR="${PROMETHEUS_BASE}/pids"
PROMETHEUS_DATA_DIR="${PROMETHEUS_BASE}/data"
PROMETHEUS_CONFIG_FILE="${PROMETHEUS_BASE}/prometheus.yml"
PROMETHEUS_PID_FILE="${PROMETHEUS_PID_DIR}/prometheus.pid"
PROMETHEUS_LOG_FILE="${PROMETHEUS_LOG_DIR}/prometheus.log"
GRAFANA_LOG_DIR="${GRAFANA_BASE}/logs"
GRAFANA_PID_DIR="${GRAFANA_BASE}/pids"
GRAFANA_DATA_DIR="${GRAFANA_BASE}/data"
GRAFANA_PROVISIONING_DIR="${GRAFANA_BASE}/provisioning"
GRAFANA_DASHBOARD_DIR="${GRAFANA_BASE}/dashboards"
GRAFANA_PLUGIN_DIR="${GRAFANA_BASE}/plugins"
GRAFANA_PID_FILE="${GRAFANA_PID_DIR}/grafana.pid"
GRAFANA_LOG_FILE="${GRAFANA_LOG_DIR}/grafana.log"
HEALTH_EXPORTER_LOG_DIR="${HEALTH_EXPORTER_BASE}/logs"
HEALTH_EXPORTER_PID_DIR="${HEALTH_EXPORTER_BASE}/pids"
HEALTH_EXPORTER_PID_FILE="${HEALTH_EXPORTER_PID_DIR}/health-exporter.pid"
HEALTH_EXPORTER_LOG_FILE="${HEALTH_EXPORTER_LOG_DIR}/health-exporter.log"
HEALTH_EXPORTER_SCRIPT="${MONITORING_SCRIPT_DIR}/health_exporter.py"
PROMETHEUS_TEMPLATE="${MONITORING_SCRIPT_DIR}/prometheus.yml"
GRAFANA_DATASOURCE_TEMPLATE="${MONITORING_SCRIPT_DIR}/grafana-datasource.yml"
GRAFANA_DASHBOARDS_TEMPLATE="${MONITORING_SCRIPT_DIR}/grafana-dashboards.yml"
GRAFANA_OVERVIEW_TEMPLATE="${MONITORING_SCRIPT_DIR}/data-lab-overview.json"

: "${PROMETHEUS_PORT:=9095}"
: "${GRAFANA_PORT:=3001}"
: "${GRAFANA_ADMIN_USER:=admin}"
: "${GRAFANA_ADMIN_PASSWORD:=admin}"
: "${PROMETHEUS_HOME:=/opt/prometheus}"
: "${GRAFANA_HOME:=/opt/grafana}"
: "${HEALTH_EXPORTER_PORT:=9105}"

PROMETHEUS_PORT="$(strip_cr "${PROMETHEUS_PORT}")"
GRAFANA_PORT="$(strip_cr "${GRAFANA_PORT}")"
GRAFANA_ADMIN_USER="$(strip_cr "${GRAFANA_ADMIN_USER}")"
GRAFANA_ADMIN_PASSWORD="$(strip_cr "${GRAFANA_ADMIN_PASSWORD}")"
PROMETHEUS_HOME="$(strip_cr "${PROMETHEUS_HOME}")"
GRAFANA_HOME="$(strip_cr "${GRAFANA_HOME}")"
HEALTH_EXPORTER_PORT="$(strip_cr "${HEALTH_EXPORTER_PORT}")"

monitoring::ensure_dirs() {
  mkdir -p \
    "${PROMETHEUS_LOG_DIR}" "${PROMETHEUS_PID_DIR}" "${PROMETHEUS_DATA_DIR}" \
    "${GRAFANA_LOG_DIR}" "${GRAFANA_PID_DIR}" "${GRAFANA_DATA_DIR}" \
    "${GRAFANA_PROVISIONING_DIR}/datasources" "${GRAFANA_PROVISIONING_DIR}/dashboards" \
    "${GRAFANA_DASHBOARD_DIR}" "${GRAFANA_PLUGIN_DIR}" \
    "${HEALTH_EXPORTER_LOG_DIR}" "${HEALTH_EXPORTER_PID_DIR}"
}

monitoring::pid_alive() {
  local pid_file="$1"
  [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null
}

monitoring::cleanup_stale_pid() {
  local pid_file="$1"
  if [[ -f "${pid_file}" ]] && ! monitoring::pid_alive "${pid_file}"; then
    rm -f "${pid_file}"
  fi
}

monitoring::port_open() {
  local host="$1" port="$2"
  MONITORING_WAIT_HOST="${host}" MONITORING_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ['MONITORING_WAIT_HOST']
port = int(os.environ['MONITORING_WAIT_PORT'])
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

monitoring::kill_pid_on_port() {
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

monitoring::sync_assets() {
  monitoring::ensure_dirs
  cp "${PROMETHEUS_TEMPLATE}" "${PROMETHEUS_CONFIG_FILE}"
  cp "${GRAFANA_DATASOURCE_TEMPLATE}" "${GRAFANA_PROVISIONING_DIR}/datasources/prometheus.yml"
  cp "${GRAFANA_DASHBOARDS_TEMPLATE}" "${GRAFANA_PROVISIONING_DIR}/dashboards/dashboards.yml"
  cp "${GRAFANA_OVERVIEW_TEMPLATE}" "${GRAFANA_DASHBOARD_DIR}/data-lab-overview.json"
}

monitoring::health_exporter_ready() {
  curl -fsS "http://127.0.0.1:${HEALTH_EXPORTER_PORT}/health" >/dev/null 2>&1
}

monitoring::prometheus_ready() {
  curl -fsS "http://127.0.0.1:${PROMETHEUS_PORT}/-/healthy" >/dev/null 2>&1
}

monitoring::grafana_ready() {
  curl -fsS "http://127.0.0.1:${GRAFANA_PORT}/api/health" >/dev/null 2>&1
}

monitoring::wait_ready() {
  local kind="$1"
  local deadline=$((SECONDS + 90))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if "monitoring::${kind}_ready"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

monitoring::start_health_exporter() {
  monitoring::ensure_dirs
  monitoring::cleanup_stale_pid "${HEALTH_EXPORTER_PID_FILE}"

  if monitoring::pid_alive "${HEALTH_EXPORTER_PID_FILE}" && monitoring::health_exporter_ready; then
    echo "[*] Data Lab health exporter already running (PID $(cat "${HEALTH_EXPORTER_PID_FILE}"))."
    return 0
  fi

  if monitoring::port_open localhost "${HEALTH_EXPORTER_PORT}"; then
    if monitoring::health_exporter_ready; then
      echo "[*] Data Lab health exporter already reachable on ${HEALTH_EXPORTER_PORT}."
      return 0
    fi
    monitoring::kill_pid_on_port "${HEALTH_EXPORTER_PORT}"
  fi

  echo "[*] Starting Data Lab health exporter on http://localhost:${HEALTH_EXPORTER_PORT}/metrics..."
  HEALTH_EXPORTER_HOST=0.0.0.0 \
  HEALTH_EXPORTER_PORT="${HEALTH_EXPORTER_PORT}" \
  nohup python3 "${HEALTH_EXPORTER_SCRIPT}" > "${HEALTH_EXPORTER_LOG_FILE}" 2>&1 &
  echo $! > "${HEALTH_EXPORTER_PID_FILE}"

  if ! monitoring::wait_ready health_exporter; then
    echo "[!] Data Lab health exporter failed to become ready. Recent log lines:" >&2
    tail -n 80 "${HEALTH_EXPORTER_LOG_FILE}" >&2 || true
    return 1
  fi
}

monitoring::start_prometheus() {
  monitoring::sync_assets
  monitoring::cleanup_stale_pid "${PROMETHEUS_PID_FILE}"
  monitoring::start_health_exporter

  if monitoring::pid_alive "${PROMETHEUS_PID_FILE}" && monitoring::prometheus_ready; then
    echo "[*] Prometheus already running (PID $(cat "${PROMETHEUS_PID_FILE}"))."
    return 0
  fi

  if monitoring::port_open localhost "${PROMETHEUS_PORT}"; then
    if monitoring::prometheus_ready; then
      echo "[*] Prometheus already reachable on ${PROMETHEUS_PORT}."
      return 0
    fi
    monitoring::kill_pid_on_port "${PROMETHEUS_PORT}"
  fi

  echo "[*] Starting Prometheus on http://localhost:${PROMETHEUS_PORT}/..."
  nohup "${PROMETHEUS_HOME}/prometheus" \
    --config.file="${PROMETHEUS_CONFIG_FILE}" \
    --storage.tsdb.path="${PROMETHEUS_DATA_DIR}" \
    --web.listen-address="0.0.0.0:${PROMETHEUS_PORT}" \
    > "${PROMETHEUS_LOG_FILE}" 2>&1 &
  echo $! > "${PROMETHEUS_PID_FILE}"

  if ! monitoring::wait_ready prometheus; then
    echo "[!] Prometheus failed to become ready. Recent log lines:" >&2
    tail -n 80 "${PROMETHEUS_LOG_FILE}" >&2 || true
    return 1
  fi

  echo "Prometheus UI: $(common::ui_url "${PROMETHEUS_PORT}" "/")"
}

monitoring::start_grafana() {
  monitoring::sync_assets
  monitoring::cleanup_stale_pid "${GRAFANA_PID_FILE}"
  monitoring::start_prometheus

  if monitoring::pid_alive "${GRAFANA_PID_FILE}" && monitoring::grafana_ready; then
    echo "[*] Grafana already running (PID $(cat "${GRAFANA_PID_FILE}"))."
    return 0
  fi

  if monitoring::port_open localhost "${GRAFANA_PORT}"; then
    if monitoring::grafana_ready; then
      echo "[*] Grafana already reachable on ${GRAFANA_PORT}."
      return 0
    fi
    monitoring::kill_pid_on_port "${GRAFANA_PORT}"
  fi

  echo "[*] Starting Grafana on http://localhost:${GRAFANA_PORT}/..."
  GF_SERVER_HTTP_ADDR=0.0.0.0 \
  GF_SERVER_HTTP_PORT="${GRAFANA_PORT}" \
  GF_SECURITY_ADMIN_USER="${GRAFANA_ADMIN_USER}" \
  GF_SECURITY_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD}" \
  GF_USERS_ALLOW_SIGN_UP=false \
  GF_METRICS_ENABLED=true \
  GF_PATHS_DATA="${GRAFANA_DATA_DIR}" \
  GF_PATHS_LOGS="${GRAFANA_LOG_DIR}" \
  GF_PATHS_PLUGINS="${GRAFANA_PLUGIN_DIR}" \
  GF_PATHS_PROVISIONING="${GRAFANA_PROVISIONING_DIR}" \
  nohup "${GRAFANA_HOME}/bin/grafana" server \
    --homepath "${GRAFANA_HOME}" \
    --config "${GRAFANA_HOME}/conf/defaults.ini" \
    > "${GRAFANA_LOG_FILE}" 2>&1 &
  echo $! > "${GRAFANA_PID_FILE}"

  if ! monitoring::wait_ready grafana; then
    echo "[!] Grafana failed to become ready. Recent log lines:" >&2
    tail -n 80 "${GRAFANA_LOG_FILE}" >&2 || true
    return 1
  fi

  echo "Grafana UI: $(common::ui_url "${GRAFANA_PORT}" "/") (login: ${GRAFANA_ADMIN_USER} / ${GRAFANA_ADMIN_PASSWORD})"
}

monitoring::start() {
  monitoring::start_prometheus
  monitoring::start_grafana
}

monitoring::stop_grafana() {
  monitoring::cleanup_stale_pid "${GRAFANA_PID_FILE}"
  if monitoring::pid_alive "${GRAFANA_PID_FILE}"; then
    echo "[*] Stopping Grafana..."
    kill "$(cat "${GRAFANA_PID_FILE}")" 2>/dev/null || true
    rm -f "${GRAFANA_PID_FILE}"
    sleep 1
  else
    rm -f "${GRAFANA_PID_FILE}"
  fi
  pkill -f "grafana server" >/dev/null 2>&1 || true
}

monitoring::stop_prometheus() {
  monitoring::cleanup_stale_pid "${PROMETHEUS_PID_FILE}"
  if monitoring::pid_alive "${PROMETHEUS_PID_FILE}"; then
    echo "[*] Stopping Prometheus..."
    kill "$(cat "${PROMETHEUS_PID_FILE}")" 2>/dev/null || true
    rm -f "${PROMETHEUS_PID_FILE}"
    sleep 1
  else
    rm -f "${PROMETHEUS_PID_FILE}"
  fi
  pkill -f "${PROMETHEUS_HOME}/prometheus" >/dev/null 2>&1 || true
}

monitoring::stop_health_exporter() {
  monitoring::cleanup_stale_pid "${HEALTH_EXPORTER_PID_FILE}"
  if monitoring::pid_alive "${HEALTH_EXPORTER_PID_FILE}"; then
    echo "[*] Stopping Data Lab health exporter..."
    kill "$(cat "${HEALTH_EXPORTER_PID_FILE}")" 2>/dev/null || true
    rm -f "${HEALTH_EXPORTER_PID_FILE}"
    sleep 1
  else
    rm -f "${HEALTH_EXPORTER_PID_FILE}"
  fi
  pkill -f "health_exporter.py" >/dev/null 2>&1 || true
}

monitoring::stop() {
  monitoring::stop_grafana
  monitoring::stop_prometheus
  monitoring::stop_health_exporter
}

monitoring::status() {
  local ok=0
  if monitoring::health_exporter_ready; then
    echo "[+] Data Lab health exporter is ready on port ${HEALTH_EXPORTER_PORT}."
  else
    echo "[-] Data Lab health exporter is not ready."
    ok=1
  fi
  if monitoring::prometheus_ready; then
    echo "[+] Prometheus is ready on port ${PROMETHEUS_PORT}."
  else
    echo "[-] Prometheus is not ready."
    ok=1
  fi
  if monitoring::grafana_ready; then
    echo "[+] Grafana is ready on port ${GRAFANA_PORT}."
  else
    echo "[-] Grafana is not ready."
    ok=1
  fi
  return "${ok}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-start}"
  case "${cmd}" in
    start)
      monitoring::start
      ;;
    stop)
      monitoring::stop
      ;;
    restart)
      monitoring::stop || true
      sleep 1
      monitoring::start
      ;;
    status)
      monitoring::status
      ;;
    *)
      echo "Usage: $0 {start|stop|restart|status}" >&2
      exit 2
      ;;
  esac
fi
