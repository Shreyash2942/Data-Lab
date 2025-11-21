#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

KAFKA_ZK_PID_FILE="${KAFKA_PID_DIR}/zookeeper.pid"
KAFKA_BROKER_PID_FILE="${KAFKA_PID_DIR}/kafka.pid"
KAFKA_ZK_LOG="${KAFKA_LOG_DIR}/zookeeper.log"
KAFKA_BROKER_LOG="${KAFKA_LOG_DIR}/kafka.log"
: "${KAFKA_ZK_PORT:=2181}"
: "${KAFKA_BROKER_PORT:=9092}"
KAFKA_ZK_PORT="$(strip_cr "${KAFKA_ZK_PORT}")"
KAFKA_BROKER_PORT="$(strip_cr "${KAFKA_BROKER_PORT}")"

kafka::ensure_dirs() {
  mkdir -p "${KAFKA_PID_DIR}" "${KAFKA_LOG_DIR}" "${KAFKA_ZK_DATA_DIR}"
}

kafka::pid_alive() {
  local pid_file="$1"
  [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null
}

kafka::cleanup_stale_pids() {
  if [[ -f "${KAFKA_ZK_PID_FILE}" ]] && ! kafka::pid_alive "${KAFKA_ZK_PID_FILE}"; then
    rm -f "${KAFKA_ZK_PID_FILE}"
  fi
  if [[ -f "${KAFKA_BROKER_PID_FILE}" ]] && ! kafka::pid_alive "${KAFKA_BROKER_PID_FILE}"; then
    rm -f "${KAFKA_BROKER_PID_FILE}"
  fi
}

kafka::port_open() {
  local host="$1" port="$2"
  KAFKA_WAIT_HOST="${host}" KAFKA_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["KAFKA_WAIT_HOST"]
port = int(os.environ["KAFKA_WAIT_PORT"])
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

kafka::wait_for_port() {
  local host="$1" port="$2" deadline
  deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if kafka::port_open "${host}" "${port}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

kafka::start_zookeeper() {
  kafka::cleanup_stale_pids
  if kafka::pid_alive "${KAFKA_ZK_PID_FILE}" && kafka::port_open localhost "${KAFKA_ZK_PORT}"; then
    echo "[*] Zookeeper already running (PID $(cat "${KAFKA_ZK_PID_FILE}"))."
    return
  fi
  if kafka::port_open localhost "${KAFKA_ZK_PORT}"; then
    echo "[!] Port ${KAFKA_ZK_PORT} is in use; assuming Zookeeper is already running."
    return
  fi
  echo "[*] Starting Zookeeper..."
  LOG_DIR="${KAFKA_LOG_DIR}" ZOO_LOG_DIR="${KAFKA_LOG_DIR}" \
  nohup "${KAFKA_HOME}/bin/zookeeper-server-start.sh" "${KAFKA_HOME}/config/zookeeper.properties" \
    > "${KAFKA_ZK_LOG}" 2>&1 &
  echo $! > "${KAFKA_ZK_PID_FILE}"
  if ! kafka::wait_for_port localhost "${KAFKA_ZK_PORT}"; then
    echo "[!] Zookeeper failed to open port ${KAFKA_ZK_PORT}. Recent log lines:" >&2
    tail -n 40 "${KAFKA_ZK_LOG}" >&2 || true
    return 1
  fi
}

kafka::start_broker() {
  kafka::cleanup_stale_pids
  if kafka::pid_alive "${KAFKA_BROKER_PID_FILE}" && kafka::port_open localhost "${KAFKA_BROKER_PORT}"; then
    echo "[*] Kafka already running (PID $(cat "${KAFKA_BROKER_PID_FILE}"))."
    return
  fi
  if kafka::port_open localhost "${KAFKA_BROKER_PORT}"; then
    echo "[!] Port ${KAFKA_BROKER_PORT} is in use; assuming Kafka broker is already running."
    return
  fi
  echo "[*] Starting Kafka broker..."
  LOG_DIR="${KAFKA_LOG_DIR}" \
  nohup "${KAFKA_HOME}/bin/kafka-server-start.sh" "${KAFKA_HOME}/config/server.properties" \
    > "${KAFKA_BROKER_LOG}" 2>&1 &
  echo $! > "${KAFKA_BROKER_PID_FILE}"
  if ! kafka::wait_for_port localhost "${KAFKA_BROKER_PORT}"; then
    echo "[!] Kafka broker failed to open port ${KAFKA_BROKER_PORT}. Recent log lines:" >&2
    tail -n 40 "${KAFKA_BROKER_LOG}" >&2 || true
    return 1
  fi
}

kafka::start() {
  kafka::ensure_dirs
  kafka::cleanup_stale_pids
  if ! kafka::start_zookeeper; then
    echo "[!] Failed to start Zookeeper; aborting Kafka startup." >&2
    return 1
  fi
  if ! kafka::start_broker; then
    echo "[!] Failed to start Kafka broker; see logs above." >&2
    return 1
  fi
  echo "Kafka broker listening on localhost:${KAFKA_BROKER_PORT}"
}

kafka::stop_broker() {
  if kafka::pid_alive "${KAFKA_BROKER_PID_FILE}"; then
    kill "$(cat "${KAFKA_BROKER_PID_FILE}")" || true
    rm -f "${KAFKA_BROKER_PID_FILE}"
  else
    LOG_DIR="${KAFKA_LOG_DIR}" "${KAFKA_HOME}/bin/kafka-server-stop.sh" || true
  fi
}

kafka::stop_zookeeper() {
  if kafka::pid_alive "${KAFKA_ZK_PID_FILE}"; then
    kill "$(cat "${KAFKA_ZK_PID_FILE}")" || true
    rm -f "${KAFKA_ZK_PID_FILE}"
  else
    LOG_DIR="${KAFKA_LOG_DIR}" ZOO_LOG_DIR="${KAFKA_LOG_DIR}" "${KAFKA_HOME}/bin/zookeeper-server-stop.sh" || true
  fi
}

kafka::stop() {
  echo "[*] Stopping Kafka services..."
  kafka::stop_broker
  kafka::stop_zookeeper
}
