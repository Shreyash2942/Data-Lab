#!/usr/bin/env bash
set -euo pipefail

# Lightweight Kafka UI runner (Kafdrop) inside the data-lab container.
# Downloads the Kafdrop fat JAR on first run and starts it on port 9002 by default.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

KAFDROP_VERSION="${KAFDROP_VERSION:-3.31.0}"
KAFDROP_PORT="${KAFDROP_PORT:-9002}"
# Optional space-separated fallback list tried if the requested port is busy.
# The first entry should match KAFDROP_PORT.
KAFDROP_PORT_CANDIDATES="${KAFDROP_PORT_CANDIDATES:-${KAFDROP_PORT} 19002 29002}"
KAFDROP_MGMT_PORT="${KAFDROP_MGMT_PORT:-}"
KAFDROP_DIR="${RUNTIME_ROOT}/kafdrop"
KAFDROP_JAR="${KAFDROP_DIR}/kafdrop-${KAFDROP_VERSION}.jar"
KAFDROP_PID_FILE="${KAFDROP_DIR}/kafdrop.pid"
KAFDROP_LOG_FILE="${KAFDROP_DIR}/kafdrop.log"
KAFDROP_URL="https://github.com/obsidiandynamics/kafdrop/releases/download/${KAFDROP_VERSION}/kafdrop-${KAFDROP_VERSION}.jar"
KAFDROP_CFG_OVERRIDE="${KAFDROP_DIR}/application-override.yml"

mkdir -p "${KAFDROP_DIR}"

ui::pid_alive() {
  [[ -f "${KAFDROP_PID_FILE}" ]] || return 1
  local pid state
  pid="$(cat "${KAFDROP_PID_FILE}")"
  kill -0 "${pid}" 2>/dev/null || return 1

  # A zombie process still answers kill -0 but cannot serve traffic.
  if [[ -r "/proc/${pid}/stat" ]]; then
    state="$(awk '{print $3}' "/proc/${pid}/stat" 2>/dev/null || true)"
    if [[ "${state}" == "Z" ]]; then
      return 1
    fi
  fi
  return 0
}

ui::cleanup_stale_pid() {
  if [[ -f "${KAFDROP_PID_FILE}" ]] && ! ui::pid_alive; then
    rm -f "${KAFDROP_PID_FILE}"
  fi
}

ui::download() {
  if [[ -f "${KAFDROP_JAR}" ]]; then
    return 0
  fi
  echo "[*] Downloading Kafdrop ${KAFDROP_VERSION}..."
  if command -v curl >/dev/null 2>&1; then
    curl -fL "${KAFDROP_URL}" -o "${KAFDROP_JAR}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${KAFDROP_JAR}" "${KAFDROP_URL}"
  else
    echo "[!] Need curl or wget inside the container to download Kafdrop." >&2
    exit 1
  fi
}

ui::port_open() {
  local host="$1" port="$2"
  KAFDROP_WAIT_HOST="${host}" KAFDROP_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["KAFDROP_WAIT_HOST"]
port = int(os.environ["KAFDROP_WAIT_PORT"])
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

ui::wait_for_port() {
  local host="$1" port="$2" deadline
  deadline=$((SECONDS + 30))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if ui::port_open "${host}" "${port}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

ui::pick_port() {
  local chosen="" candidate
  for candidate in ${KAFDROP_PORT_CANDIDATES}; do
    if ! ui::port_open localhost "${candidate}"; then
      chosen="${candidate}"
      break
    fi
  done
  if [[ -z "${chosen}" ]]; then
    echo "[!] No free port found from: ${KAFDROP_PORT_CANDIDATES}" >&2
    return 1
  fi
  KAFDROP_PORT="${chosen}"
}

ui::start() {
  ui::cleanup_stale_pid
  local mgmt_port="${KAFDROP_MGMT_PORT:-${KAFDROP_PORT}}"

  if ui::pid_alive; then
    echo "[*] Kafka UI (Kafdrop) already running (PID $(cat "${KAFDROP_PID_FILE}"))."
    echo "    URL: $(common::ui_url "${KAFDROP_PORT}" "/")"
    return 0
  fi

  if ui::port_open localhost "${KAFDROP_PORT}"; then
    echo "[!] Port ${KAFDROP_PORT} is already in use. Trying fallbacks: ${KAFDROP_PORT_CANDIDATES}..." >&2
    if ! ui::pick_port; then
      return 1
    fi
    echo "[*] Using free port ${KAFDROP_PORT}."
    mgmt_port="${KAFDROP_MGMT_PORT:-${KAFDROP_PORT}}"
  fi
  if [[ "${mgmt_port}" != "${KAFDROP_PORT}" ]] && ui::port_open localhost "${mgmt_port}"; then
    echo "[!] Management port ${mgmt_port} is already in use. Set KAFDROP_MGMT_PORT to a free port and retry." >&2
    return 1
  fi

  ui::download
  cat > "${KAFDROP_CFG_OVERRIDE}" <<EOF
server:
  port: ${KAFDROP_PORT}
  address: 0.0.0.0
management:
  server:
    port: ${mgmt_port}
kafka:
  brokerConnect: localhost:9092
EOF

  echo "[*] Starting Kafdrop on $(common::ui_url "${KAFDROP_PORT}" "/") (logs: ${KAFDROP_LOG_FILE})..."
  JAVA_PROPS=(
    "-Dserver.port=${KAFDROP_PORT}"
    "-Dserver.address=0.0.0.0"
    "-Dkafka.brokerConnect=localhost:9092"
    "-Dmanagement.server.port=${mgmt_port}"
    "-Dmanagement.port=${mgmt_port}"
  )
  local spring_json
  spring_json=$(cat <<EOF
{"server":{"port":${KAFDROP_PORT},"address":"0.0.0.0"},"management":{"server":{"port":${mgmt_port}}},"kafka":{"brokerConnect":"localhost:9092"}}
EOF
)
  SPRING_APPLICATION_JSON="${spring_json}" \
  SPRING_CONFIG_LOCATION="classpath:/application.yml,file:${KAFDROP_CFG_OVERRIDE}" \
  nohup java "${JAVA_PROPS[@]}" -jar "${KAFDROP_JAR}" \
    > "${KAFDROP_LOG_FILE}" 2>&1 &

  echo $! > "${KAFDROP_PID_FILE}"
  if ! ui::wait_for_port localhost "${KAFDROP_PORT}"; then
    echo "[!] Kafdrop failed to open port ${KAFDROP_PORT}; see ${KAFDROP_LOG_FILE}" >&2
    tail -n 60 "${KAFDROP_LOG_FILE}" 2>/dev/null || true
    rm -f "${KAFDROP_PID_FILE}"
    exit 1
  fi
  echo "[+] Kafdrop started (PID $(cat "${KAFDROP_PID_FILE}")) -> $(common::ui_url "${KAFDROP_PORT}" "/")"
}

ui::stop() {
  if ui::pid_alive; then
    kill "$(cat "${KAFDROP_PID_FILE}")" 2>/dev/null || true
    rm -f "${KAFDROP_PID_FILE}"
    echo "[+] Kafdrop stopped."
  else
    echo "[*] Kafdrop not running."
  fi
}

ui::status() {
  ui::cleanup_stale_pid
  if ui::pid_alive; then
    echo "[+] Kafdrop running (PID $(cat "${KAFDROP_PID_FILE}")) on $(common::ui_url "${KAFDROP_PORT}" "/")"
  else
    echo "[-] Kafdrop not running."
  fi
}

case "${1:-}" in
  start) ui::start ;;
  stop) ui::stop ;;
  status) ui::status ;;
  restart) ui::stop; ui::start ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}" >&2
    exit 1
    ;;
esac
