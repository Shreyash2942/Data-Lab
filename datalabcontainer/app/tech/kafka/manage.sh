#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

KAFKA_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${KAFKA_SCRIPT_DIR}/../common.sh"

# Guard in case strip_cr was not loaded (e.g., if common.sh failed to source)
if ! declare -F strip_cr >/dev/null; then
  strip_cr() {
    local value="${1:-}"
    value="${value//$'\r'/}"
    printf '%s' "${value}"
  }
fi

KAFKA_ZK_PID_FILE="${KAFKA_PID_DIR}/zookeeper.pid"
KAFKA_BROKER_PID_FILE="${KAFKA_PID_DIR}/kafka.pid"
KAFKA_ZK_LOG="${KAFKA_LOG_DIR}/zookeeper.log"
KAFKA_BROKER_LOG="${KAFKA_LOG_DIR}/kafka.log"
KAFKA_BROKER_CONFIG="${KAFKA_BASE}/server.properties"
KAFKA_JAVA_NET_OPTS="-Djava.net.preferIPv4Stack=true -Djava.net.preferIPv6Addresses=false"
: "${KAFKA_ZK_PORT:=2181}"
: "${KAFKA_BROKER_PORT:=9092}"
KAFKA_ZK_PORT="$(strip_cr "${KAFKA_ZK_PORT}")"
KAFKA_BROKER_PORT="$(strip_cr "${KAFKA_BROKER_PORT}")"
: "${KAFKA_BROKER_ID:=}"

kafka::broker_id() {
  # Prefer explicit env, otherwise read from server.properties, default to 1.
  if [[ -n "${KAFKA_BROKER_ID}" ]]; then
    printf '%s' "${KAFKA_BROKER_ID}"
    return
  fi
  if [[ -f "${KAFKA_HOME}/config/server.properties" ]]; then
    local id
    id="$(grep -E '^broker.id=' "${KAFKA_HOME}/config/server.properties" | tail -n1 | cut -d'=' -f2)"
    id="$(strip_cr "${id:-}")"
    if [[ -n "${id}" ]]; then
      printf '%s' "${id}"
      return
    fi
  fi
  printf '1'
}

kafka::clear_stale_znode() {
  local bid
  bid="$(kafka::broker_id)"
  echo "[*] Attempting to clear stale broker znode /brokers/ids/${bid}..."
  "${KAFKA_HOME}/bin/zookeeper-shell.sh" "127.0.0.1:${KAFKA_ZK_PORT}" deleteall "/brokers/ids/${bid}" >/dev/null 2>&1 || true
}

kafka::ensure_dirs() {
  mkdir -p "${KAFKA_PID_DIR}" "${KAFKA_LOG_DIR}" "${KAFKA_DATA_DIR}" "${KAFKA_ZK_DATA_DIR}"
}

kafka::render_broker_config() {
  local src="${KAFKA_HOME}/config/server.properties"
  local dst="${KAFKA_BROKER_CONFIG}"

  cp "${src}" "${dst}"
  sed -i \
    -e "s|^broker.id=.*|broker.id=$(kafka::broker_id)|" \
    -e "s|^listeners=.*|listeners=PLAINTEXT://0.0.0.0:${KAFKA_BROKER_PORT}|" \
    -e "s|^advertised.listeners=.*|advertised.listeners=PLAINTEXT://127.0.0.1:${KAFKA_BROKER_PORT}|" \
    -e "s|^zookeeper.connect=.*|zookeeper.connect=127.0.0.1:${KAFKA_ZK_PORT}|" \
    -e "s|^log.dirs=.*|log.dirs=${KAFKA_DATA_DIR}|" \
    "${dst}"

  if [[ ! -w "${KAFKA_DATA_DIR}" ]]; then
    echo "[!] Kafka data dir is not writable: ${KAFKA_DATA_DIR}" >&2
    return 1
  fi
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

kafka::broker_ready() {
  "${KAFKA_HOME}/bin/kafka-topics.sh" --bootstrap-server "localhost:${KAFKA_BROKER_PORT}" --list >/dev/null 2>&1
}

kafka::zk_ready() {
  "${KAFKA_HOME}/bin/zookeeper-shell.sh" "127.0.0.1:${KAFKA_ZK_PORT}" ls / >/dev/null 2>&1
}

kafka::wait_for_zk_ready() {
  local deadline
  deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if kafka::zk_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

kafka::wait_for_broker_ready() {
  local deadline
  deadline=$((SECONDS + 90))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if kafka::broker_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

kafka::kill_pid_on_port() {
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

kafka::start_zookeeper() {
  kafka::cleanup_stale_pids
  if kafka::pid_alive "${KAFKA_ZK_PID_FILE}" && kafka::port_open localhost "${KAFKA_ZK_PORT}" && kafka::zk_ready; then
    echo "[*] Zookeeper already running (PID $(cat "${KAFKA_ZK_PID_FILE}"))."
    return
  fi
  if kafka::port_open localhost "${KAFKA_ZK_PORT}"; then
    if kafka::zk_ready; then
      echo "[*] Zookeeper already reachable on ${KAFKA_ZK_PORT}."
      return
    fi
    kafka::kill_pid_on_port "${KAFKA_ZK_PORT}"
    if kafka::port_open localhost "${KAFKA_ZK_PORT}"; then
      echo "[!] Port ${KAFKA_ZK_PORT} is in use by an unhealthy listener and could not be cleared." >&2
      return 1
    fi
  fi
  echo "[*] Starting Zookeeper..."
  LOG_DIR="${KAFKA_LOG_DIR}" ZOO_LOG_DIR="${KAFKA_LOG_DIR}" KAFKA_OPTS="${KAFKA_JAVA_NET_OPTS}" \
  nohup "${KAFKA_HOME}/bin/zookeeper-server-start.sh" "${KAFKA_HOME}/config/zookeeper.properties" \
    > "${KAFKA_ZK_LOG}" 2>&1 &
  echo $! > "${KAFKA_ZK_PID_FILE}"
  if ! kafka::wait_for_port localhost "${KAFKA_ZK_PORT}"; then
    echo "[!] Zookeeper failed to open port ${KAFKA_ZK_PORT}. Recent log lines:" >&2
    tail -n 40 "${KAFKA_ZK_LOG}" >&2 || true
    return 1
  fi
  if ! kafka::wait_for_zk_ready; then
    echo "[!] Zookeeper port is open but API is not ready. Recent log lines:" >&2
    tail -n 60 "${KAFKA_ZK_LOG}" >&2 || true
    return 1
  fi
}

kafka::start_broker() {
  # Clear any stale broker znode before the first start to avoid KeeperErrorCode=NodeExists
  kafka::clear_stale_znode
  kafka::cleanup_stale_pids
  if kafka::pid_alive "${KAFKA_BROKER_PID_FILE}" && kafka::port_open localhost "${KAFKA_BROKER_PORT}" && kafka::broker_ready; then
    echo "[*] Kafka already running (PID $(cat "${KAFKA_BROKER_PID_FILE}"))."
    return
  fi
  if kafka::port_open localhost "${KAFKA_BROKER_PORT}"; then
    if kafka::broker_ready; then
      echo "[*] Kafka broker already reachable on ${KAFKA_BROKER_PORT}."
      return
    fi
    kafka::kill_pid_on_port "${KAFKA_BROKER_PORT}"
    if kafka::port_open localhost "${KAFKA_BROKER_PORT}"; then
      echo "[!] Port ${KAFKA_BROKER_PORT} is in use by an unhealthy listener and could not be cleared." >&2
      return 1
    fi
  fi
  echo "[*] Starting Kafka broker..."
  if ! kafka::render_broker_config; then
    return 1
  fi
  pkill -f "kafka.Kafka" 2>/dev/null || true
  sleep 1
  LOG_DIR="${KAFKA_LOG_DIR}" KAFKA_OPTS="${KAFKA_JAVA_NET_OPTS}" \
  nohup "${KAFKA_HOME}/bin/kafka-server-start.sh" "${KAFKA_BROKER_CONFIG}" \
    > "${KAFKA_BROKER_LOG}" 2>&1 &
  echo $! > "${KAFKA_BROKER_PID_FILE}"
  if ! kafka::wait_for_port localhost "${KAFKA_BROKER_PORT}"; then
    echo "[!] Kafka broker failed to open port ${KAFKA_BROKER_PORT}. Recent log lines:" >&2
    tail -n 40 "${KAFKA_BROKER_LOG}" >&2 || true
    # Handle common stale znode error once, then retry.
    if grep -q "KeeperErrorCode = NodeExists" "${KAFKA_BROKER_LOG}" 2>/dev/null; then
      kafka::clear_stale_znode
      echo "[*] Retrying Kafka broker start after clearing stale znode..."
      rm -f "${KAFKA_BROKER_PID_FILE}"
      if ! kafka::render_broker_config; then
        return 1
      fi
      LOG_DIR="${KAFKA_LOG_DIR}" KAFKA_OPTS="${KAFKA_JAVA_NET_OPTS}" \
      nohup "${KAFKA_HOME}/bin/kafka-server-start.sh" "${KAFKA_BROKER_CONFIG}" \
        > "${KAFKA_BROKER_LOG}" 2>&1 &
      echo $! > "${KAFKA_BROKER_PID_FILE}"
      if ! kafka::wait_for_port localhost "${KAFKA_BROKER_PORT}"; then
        echo "[!] Kafka broker retry failed to open port ${KAFKA_BROKER_PORT}. Recent log lines:" >&2
        tail -n 40 "${KAFKA_BROKER_LOG}" >&2 || true
        return 1
      fi
    else
      return 1
    fi
  fi
  if ! kafka::wait_for_broker_ready; then
    echo "[!] Kafka port is open but broker API is not ready. Recent log lines:" >&2
    tail -n 80 "${KAFKA_BROKER_LOG}" >&2 || true
    return 1
  fi
}

kafka::start_ui() {
  local ui_script="${KAFKA_SCRIPT_DIR}/ui.sh"
  if [[ ! -x "${ui_script}" ]]; then
    echo "[!] Kafka UI script not found at ${ui_script}" >&2
    return 0
  fi
  echo "[*] Starting Kafka UI (Kafdrop)..."
  if ! bash "${ui_script}" start; then
    echo "[!] Kafka UI failed to start; see runtime/kafdrop/kafdrop.log" >&2
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
  kafka::start_ui
  local host_bootstrap
  host_bootstrap="${DATALAB_UI_HOST}:$(common::mapped_host_port "${KAFKA_BROKER_PORT}")"
  echo "Kafka broker endpoint (host): ${host_bootstrap}"
  echo "Kafka broker endpoint (inside container): localhost:${KAFKA_BROKER_PORT}"
  local ui_port="${KAFDROP_PORT:-9002}"
  echo "Kafka UI (single-container, Kafdrop): $(common::ui_url "${ui_port}" "/")"
  echo "CLI example (inside container): kafka-topics.sh --bootstrap-server localhost:${KAFKA_BROKER_PORT} --list"
  echo "CLI example (from host): kafka-topics.sh --bootstrap-server ${host_bootstrap} --list"
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
  kafka::stop_ui
  kafka::stop_broker
  kafka::stop_zookeeper
}

kafka::stop_ui() {
  local ui_script="${KAFKA_SCRIPT_DIR}/ui.sh"
  if [[ -x "${ui_script}" ]]; then
    bash "${ui_script}" stop || true
  fi
}

kafka::status() {
  local ok=0
  if kafka::port_open localhost "${KAFKA_ZK_PORT}"; then
    echo "[+] Zookeeper port ${KAFKA_ZK_PORT} is listening."
  else
    echo "[-] Zookeeper port ${KAFKA_ZK_PORT} is not listening."
    ok=1
  fi

  if kafka::port_open localhost "${KAFKA_BROKER_PORT}"; then
    echo "[+] Kafka port ${KAFKA_BROKER_PORT} is listening."
  else
    echo "[-] Kafka port ${KAFKA_BROKER_PORT} is not listening."
    ok=1
  fi

  if kafka::zk_ready; then
    echo "[+] Zookeeper API ready."
  else
    echo "[-] Zookeeper API not ready."
    ok=1
  fi

  if kafka::broker_ready; then
    echo "[+] Kafka broker API ready."
  else
    echo "[-] Kafka broker API not ready."
    ok=1
  fi
  return "${ok}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-start}"
  case "${cmd}" in
    start)
      kafka::start
      ;;
    stop)
      kafka::stop
      ;;
    restart)
      kafka::stop || true
      sleep 1
      kafka::start
      ;;
    status)
      kafka::status
      ;;
    *)
      echo "Usage: $0 {start|stop|restart|status}" >&2
      exit 2
      ;;
  esac
fi
