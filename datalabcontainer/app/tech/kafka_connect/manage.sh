#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

KAFKA_CONNECT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${KAFKA_CONNECT_SCRIPT_DIR}/../common.sh"

if ! declare -F kafka::start >/dev/null 2>&1; then
  source "${KAFKA_CONNECT_SCRIPT_DIR}/../kafka/manage.sh"
fi

KAFKA_CONNECT_BASE="${RUNTIME_ROOT}/kafka-connect"
KAFKA_CONNECT_LOG_DIR="${KAFKA_CONNECT_BASE}/logs"
KAFKA_CONNECT_PID_DIR="${KAFKA_CONNECT_BASE}/pids"
KAFKA_CONNECT_DATA_DIR="${KAFKA_CONNECT_BASE}/data"
KAFKA_CONNECT_PLUGIN_DIR="${KAFKA_CONNECT_BASE}/plugins"
KAFKA_CONNECT_CONFIG_FILE="${KAFKA_CONNECT_BASE}/connect-distributed.properties"
KAFKA_CONNECT_PID_FILE="${KAFKA_CONNECT_PID_DIR}/kafka-connect.pid"
KAFKA_CONNECT_LOG_FILE="${KAFKA_CONNECT_LOG_DIR}/kafka-connect.log"

: "${KAFKA_CONNECT_PORT:=8086}"
: "${KAFKA_CONNECT_HOST:=0.0.0.0}"
: "${KAFKA_CONNECT_GROUP_ID:=datalab-connect-cluster}"
: "${KAFKA_CONNECT_CONFIG_TOPIC:=datalab_connect_configs}"
: "${KAFKA_CONNECT_OFFSET_TOPIC:=datalab_connect_offsets}"
: "${KAFKA_CONNECT_STATUS_TOPIC:=datalab_connect_statuses}"
: "${KAFKA_CONNECT_PLUGIN_PATH:=${KAFKA_CONNECT_PLUGIN_DIR},${KAFKA_HOME}/plugins}"
: "${KAFKA_CONNECT_JAVA_HOME:=${JAVA17_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}}"
: "${KAFKA_CONNECT_HEAP_OPTS:=-Xms384M -Xmx384M}"

KAFKA_CONNECT_PORT="$(strip_cr "${KAFKA_CONNECT_PORT}")"
KAFKA_CONNECT_HOST="$(strip_cr "${KAFKA_CONNECT_HOST}")"
KAFKA_CONNECT_GROUP_ID="$(strip_cr "${KAFKA_CONNECT_GROUP_ID}")"
KAFKA_CONNECT_CONFIG_TOPIC="$(strip_cr "${KAFKA_CONNECT_CONFIG_TOPIC}")"
KAFKA_CONNECT_OFFSET_TOPIC="$(strip_cr "${KAFKA_CONNECT_OFFSET_TOPIC}")"
KAFKA_CONNECT_STATUS_TOPIC="$(strip_cr "${KAFKA_CONNECT_STATUS_TOPIC}")"
KAFKA_CONNECT_PLUGIN_PATH="$(strip_cr "${KAFKA_CONNECT_PLUGIN_PATH}")"
KAFKA_CONNECT_JAVA_HOME="$(strip_cr "${KAFKA_CONNECT_JAVA_HOME}")"
KAFKA_CONNECT_HEAP_OPTS="$(strip_cr "${KAFKA_CONNECT_HEAP_OPTS}")"

kafka_connect::ensure_dirs() {
  mkdir -p "${KAFKA_CONNECT_LOG_DIR}" "${KAFKA_CONNECT_PID_DIR}" "${KAFKA_CONNECT_DATA_DIR}" "${KAFKA_CONNECT_PLUGIN_DIR}"
}

kafka_connect::pid_alive() {
  [[ -f "${KAFKA_CONNECT_PID_FILE}" ]] && kill -0 "$(cat "${KAFKA_CONNECT_PID_FILE}")" 2>/dev/null
}

kafka_connect::cleanup_stale_pid() {
  if [[ -f "${KAFKA_CONNECT_PID_FILE}" ]] && ! kafka_connect::pid_alive; then
    rm -f "${KAFKA_CONNECT_PID_FILE}"
  fi
}

kafka_connect::port_open() {
  local host="$1" port="$2"
  KAFKA_CONNECT_WAIT_HOST="${host}" KAFKA_CONNECT_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["KAFKA_CONNECT_WAIT_HOST"]
port = int(os.environ["KAFKA_CONNECT_WAIT_PORT"])
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

kafka_connect::api_ready() {
  curl -fsS "http://127.0.0.1:${KAFKA_CONNECT_PORT}/connectors" >/dev/null 2>&1
}

kafka_connect::wait_ready() {
  local deadline=$((SECONDS + 90))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if kafka_connect::api_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

kafka_connect::kill_pid_on_port() {
  local port="$1"
  local pids=""
  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -t -iTCP:${port} -sTCP:LISTEN 2>/dev/null | tr '\n' ' ' || true)"
  elif command -v fuser >/dev/null 2>&1; then
    pids="$(fuser -n tcp "${port}" 2>/dev/null | tr ' ' '\n' | tr '\n' ' ' || true)"
  fi
  if [[ -n "${pids// }" ]]; then
    echo "[!] Kafka Connect port ${port} is occupied by PID(s): ${pids}. Killing stale listener(s)..."
    # shellcheck disable=SC2086
    kill ${pids} 2>/dev/null || true
    sleep 1
  fi
}

kafka_connect::render_config() {
  cat > "${KAFKA_CONNECT_CONFIG_FILE}" <<EOF
bootstrap.servers=127.0.0.1:${KAFKA_BROKER_PORT}
group.id=${KAFKA_CONNECT_GROUP_ID}

key.converter=org.apache.kafka.connect.json.JsonConverter
value.converter=org.apache.kafka.connect.json.JsonConverter
key.converter.schemas.enable=false
value.converter.schemas.enable=false

config.storage.topic=${KAFKA_CONNECT_CONFIG_TOPIC}
offset.storage.topic=${KAFKA_CONNECT_OFFSET_TOPIC}
status.storage.topic=${KAFKA_CONNECT_STATUS_TOPIC}
config.storage.replication.factor=1
offset.storage.replication.factor=1
status.storage.replication.factor=1

offset.flush.interval.ms=10000
plugin.path=${KAFKA_CONNECT_PLUGIN_PATH}
listeners=http://${KAFKA_CONNECT_HOST}:${KAFKA_CONNECT_PORT}
rest.advertised.host.name=127.0.0.1
rest.advertised.port=${KAFKA_CONNECT_PORT}
EOF
}

kafka_connect::start() {
  kafka_connect::ensure_dirs
  kafka_connect::cleanup_stale_pid
  kafka::start

  if kafka_connect::pid_alive && kafka_connect::port_open localhost "${KAFKA_CONNECT_PORT}" && kafka_connect::api_ready; then
    echo "[*] Kafka Connect already running (PID $(cat "${KAFKA_CONNECT_PID_FILE}"))."
    return
  fi

  if kafka_connect::port_open localhost "${KAFKA_CONNECT_PORT}"; then
    if kafka_connect::api_ready; then
      echo "[*] Kafka Connect already reachable on ${KAFKA_CONNECT_PORT}."
      return
    fi
    kafka_connect::kill_pid_on_port "${KAFKA_CONNECT_PORT}"
    if kafka_connect::port_open localhost "${KAFKA_CONNECT_PORT}"; then
      echo "[!] Kafka Connect port ${KAFKA_CONNECT_PORT} is in use by an unhealthy listener and could not be cleared." >&2
      return 1
    fi
  fi

  kafka_connect::render_config
  echo "[*] Starting Kafka Connect on http://localhost:${KAFKA_CONNECT_PORT}/..."
  JAVA_HOME="${KAFKA_CONNECT_JAVA_HOME}" \
  PATH="${KAFKA_CONNECT_JAVA_HOME}/bin:${PATH}" \
  KAFKA_HEAP_OPTS="${KAFKA_CONNECT_HEAP_OPTS}" \
  LOG_DIR="${KAFKA_CONNECT_LOG_DIR}" \
  nohup "${KAFKA_HOME}/bin/connect-distributed.sh" "${KAFKA_CONNECT_CONFIG_FILE}" \
    > "${KAFKA_CONNECT_LOG_FILE}" 2>&1 &
  echo $! > "${KAFKA_CONNECT_PID_FILE}"

  if ! kafka_connect::wait_ready; then
    echo "[!] Kafka Connect failed to become ready. Recent log lines:" >&2
    tail -n 80 "${KAFKA_CONNECT_LOG_FILE}" >&2 || true
    return 1
  fi

  echo "Kafka Connect API: $(common::ui_url "${KAFKA_CONNECT_PORT}" "/connectors")"
}

kafka_connect::stop() {
  if kafka_connect::pid_alive; then
    echo "[*] Stopping Kafka Connect..."
    kill "$(cat "${KAFKA_CONNECT_PID_FILE}")" 2>/dev/null || true
    rm -f "${KAFKA_CONNECT_PID_FILE}"
    sleep 1
  else
    rm -f "${KAFKA_CONNECT_PID_FILE}"
  fi
}

kafka_connect::status() {
  local ok=0
  if kafka_connect::port_open localhost "${KAFKA_CONNECT_PORT}"; then
    echo "[+] Kafka Connect port ${KAFKA_CONNECT_PORT} is listening."
  else
    echo "[-] Kafka Connect port ${KAFKA_CONNECT_PORT} is not listening."
    ok=1
  fi

  if kafka_connect::api_ready; then
    echo "[+] Kafka Connect REST API is ready."
  else
    echo "[-] Kafka Connect REST API is not ready."
    ok=1
  fi
  return "${ok}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-start}"
  case "${cmd}" in
    start)
      kafka_connect::start
      ;;
    stop)
      kafka_connect::stop
      ;;
    restart)
      kafka_connect::stop || true
      sleep 1
      kafka_connect::start
      ;;
    status)
      kafka_connect::status
      ;;
    *)
      echo "Usage: $0 {start|stop|restart|status}" >&2
      exit 2
      ;;
  esac
fi
