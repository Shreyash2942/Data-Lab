#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

KAFKA_ZK_PID_FILE="${KAFKA_PID_DIR}/zookeeper.pid"
KAFKA_BROKER_PID_FILE="${KAFKA_PID_DIR}/kafka.pid"
KAFKA_ZK_LOG="${KAFKA_LOG_DIR}/zookeeper.log"
KAFKA_BROKER_LOG="${KAFKA_LOG_DIR}/kafka.log"

kafka::ensure_dirs() {
  mkdir -p "${KAFKA_PID_DIR}" "${KAFKA_LOG_DIR}" "${KAFKA_ZK_DATA_DIR}"
}

kafka::pid_alive() {
  local pid_file="$1"
  [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null
}

kafka::start_zookeeper() {
  if kafka::pid_alive "${KAFKA_ZK_PID_FILE}"; then
    echo "[*] Zookeeper already running (PID $(cat "${KAFKA_ZK_PID_FILE}"))."
    return
  fi
  echo "[*] Starting Zookeeper..."
  LOG_DIR="${KAFKA_LOG_DIR}" ZOO_LOG_DIR="${KAFKA_LOG_DIR}" \
  nohup "${KAFKA_HOME}/bin/zookeeper-server-start.sh" "${KAFKA_HOME}/config/zookeeper.properties" \
    > "${KAFKA_ZK_LOG}" 2>&1 &
  echo $! > "${KAFKA_ZK_PID_FILE}"
  sleep 5
}

kafka::start_broker() {
  if kafka::pid_alive "${KAFKA_BROKER_PID_FILE}"; then
    echo "[*] Kafka already running (PID $(cat "${KAFKA_BROKER_PID_FILE}"))."
    return
  fi
  echo "[*] Starting Kafka broker..."
  LOG_DIR="${KAFKA_LOG_DIR}" \
  nohup "${KAFKA_HOME}/bin/kafka-server-start.sh" "${KAFKA_HOME}/config/server.properties" \
    > "${KAFKA_BROKER_LOG}" 2>&1 &
  echo $! > "${KAFKA_BROKER_PID_FILE}"
  sleep 3
}

kafka::start() {
  kafka::ensure_dirs
  kafka::start_zookeeper
  kafka::start_broker
  echo "Kafka broker listening on localhost:9092"
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
