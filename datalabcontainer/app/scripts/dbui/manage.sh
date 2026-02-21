#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

DBUI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DBUI_SCRIPT_DIR}/../common.sh"

DBUI_BASE="${RUNTIME_ROOT}/dbui"
DBUI_PID_DIR="${DBUI_BASE}/pids"
DBUI_LOG_DIR="${DBUI_BASE}/logs"

ADMINER_PORT="${ADMINER_PORT:-8082}"
MONGO_EXPRESS_PORT="${MONGO_EXPRESS_PORT:-8083}"
REDIS_COMMANDER_PORT="${REDIS_COMMANDER_PORT:-8084}"

DBUI_ADMINER_DIR="${DBUI_BASE}/adminer"
DBUI_ADMINER_FILE="${DBUI_ADMINER_DIR}/index.php"
DBUI_ADMINER_PID_FILE="${DBUI_PID_DIR}/adminer.pid"
DBUI_ADMINER_LOG_FILE="${DBUI_LOG_DIR}/adminer.log"

DBUI_MONGO_EXPRESS_PID_FILE="${DBUI_PID_DIR}/mongo-express.pid"
DBUI_MONGO_EXPRESS_LOG_FILE="${DBUI_LOG_DIR}/mongo-express.log"

DBUI_REDIS_COMMANDER_PID_FILE="${DBUI_PID_DIR}/redis-commander.pid"
DBUI_REDIS_COMMANDER_LOG_FILE="${DBUI_LOG_DIR}/redis-commander.log"

dbui::ensure_dirs() {
  mkdir -p "${DBUI_BASE}" "${DBUI_PID_DIR}" "${DBUI_LOG_DIR}" "${DBUI_ADMINER_DIR}"
  if [[ "$(id -u)" -eq 0 ]]; then
    local app_user="${LAB_APP_USER:-datalab}"
    chown -R "${app_user}:${app_user}" "${DBUI_BASE}" 2>/dev/null || true
    # On Windows bind mounts chown may be ignored; keep directories writable for datalab.
    chmod 777 "${DBUI_BASE}" "${DBUI_PID_DIR}" "${DBUI_LOG_DIR}" "${DBUI_ADMINER_DIR}" 2>/dev/null || true
    [[ -f "${DBUI_ADMINER_PID_FILE}" ]] && chmod 666 "${DBUI_ADMINER_PID_FILE}" 2>/dev/null || true
    [[ -f "${DBUI_MONGO_EXPRESS_PID_FILE}" ]] && chmod 666 "${DBUI_MONGO_EXPRESS_PID_FILE}" 2>/dev/null || true
    [[ -f "${DBUI_REDIS_COMMANDER_PID_FILE}" ]] && chmod 666 "${DBUI_REDIS_COMMANDER_PID_FILE}" 2>/dev/null || true
  fi
}

dbui::pid_alive() {
  local pid_file="$1"
  [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null
}

dbui::cleanup_stale_pid() {
  local pid_file="$1"
  if [[ -f "${pid_file}" ]] && ! dbui::pid_alive "${pid_file}"; then
    rm -f "${pid_file}"
  fi
}

dbui::port_open() {
  local host="$1" port="$2"
  DBUI_WAIT_HOST="${host}" DBUI_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["DBUI_WAIT_HOST"]
port = int(os.environ["DBUI_WAIT_PORT"])
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

dbui::wait_for_port() {
  local host="$1" port="$2" deadline
  deadline=$((SECONDS + 45))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if dbui::port_open "${host}" "${port}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

dbui::download_adminer() {
  if [[ -f "${DBUI_ADMINER_FILE}" ]]; then
    return 0
  fi
  echo "[*] Downloading Adminer..."
  curl -fsSL "https://github.com/vrana/adminer/releases/download/v4.8.1/adminer-4.8.1.php" -o "${DBUI_ADMINER_FILE}"
}

dbui::start_adminer() {
  dbui::cleanup_stale_pid "${DBUI_ADMINER_PID_FILE}"
  if dbui::pid_alive "${DBUI_ADMINER_PID_FILE}" && dbui::port_open localhost "${ADMINER_PORT}"; then
    echo "[*] Adminer already running (PID $(cat "${DBUI_ADMINER_PID_FILE}"))."
    return 0
  fi

  if ! command -v php >/dev/null 2>&1; then
    echo "[!] php is not installed; cannot start Adminer." >&2
    return 1
  fi

  dbui::download_adminer
  echo "[*] Starting Adminer on $(common::ui_url "${ADMINER_PORT}" "/")..."
  nohup php -S 0.0.0.0:"${ADMINER_PORT}" -t "${DBUI_ADMINER_DIR}" > "${DBUI_ADMINER_LOG_FILE}" 2>&1 &
  echo $! > "${DBUI_ADMINER_PID_FILE}"
  if ! dbui::wait_for_port localhost "${ADMINER_PORT}"; then
    echo "[!] Adminer failed to open port ${ADMINER_PORT}; see ${DBUI_ADMINER_LOG_FILE}" >&2
    return 1
  fi
  echo "[+] Adminer started (PID $(cat "${DBUI_ADMINER_PID_FILE}"))."
}

dbui::start_mongo_express() {
  dbui::cleanup_stale_pid "${DBUI_MONGO_EXPRESS_PID_FILE}"
  if dbui::pid_alive "${DBUI_MONGO_EXPRESS_PID_FILE}" && dbui::port_open localhost "${MONGO_EXPRESS_PORT}"; then
    echo "[*] Mongo Express already running (PID $(cat "${DBUI_MONGO_EXPRESS_PID_FILE}"))."
    return 0
  fi

  if ! command -v mongo-express >/dev/null 2>&1; then
    echo "[!] mongo-express not installed; cannot start MongoDB UI." >&2
    return 1
  fi

  local mongo_port="${MONGO_PORT:-27017}"
  local mongo_user="${MONGO_ROOT_USERNAME:-datalab}"
  local mongo_pass="${MONGO_ROOT_PASSWORD:-datalab}"
  # Clean stale mongo-express processes started with older config/ports.
  pkill -f "mongo-express" >/dev/null 2>&1 || true
  echo "[*] Starting Mongo Express on $(common::ui_url "${MONGO_EXPRESS_PORT}" "/")..."
  env \
    VCAP_APP_HOST="0.0.0.0" \
    VCAP_APP_PORT="${MONGO_EXPRESS_PORT}" \
    ME_CONFIG_BASICAUTH_USERNAME="" \
    ME_CONFIG_BASICAUTH_PASSWORD="" \
    ME_CONFIG_MONGODB_SERVER="localhost" \
    ME_CONFIG_MONGODB_PORT="${mongo_port}" \
    ME_CONFIG_MONGODB_ENABLE_ADMIN="true" \
    ME_CONFIG_MONGODB_ADMINUSERNAME="${mongo_user}" \
    ME_CONFIG_MONGODB_ADMINPASSWORD="${mongo_pass}" \
    ME_CONFIG_MONGODB_AUTH_DATABASE="admin" \
    nohup mongo-express > "${DBUI_MONGO_EXPRESS_LOG_FILE}" 2>&1 &
  echo $! > "${DBUI_MONGO_EXPRESS_PID_FILE}"
  if ! dbui::wait_for_port localhost "${MONGO_EXPRESS_PORT}"; then
    echo "[!] Mongo Express failed to open port ${MONGO_EXPRESS_PORT}; see ${DBUI_MONGO_EXPRESS_LOG_FILE}" >&2
    return 1
  fi
  echo "[+] Mongo Express started (PID $(cat "${DBUI_MONGO_EXPRESS_PID_FILE}"))."
}

dbui::start_redis_commander() {
  dbui::cleanup_stale_pid "${DBUI_REDIS_COMMANDER_PID_FILE}"
  # Clean stale redis-commander processes started with older auth settings.
  pkill -f "redis-commander" >/dev/null 2>&1 || true
  if dbui::pid_alive "${DBUI_REDIS_COMMANDER_PID_FILE}" && dbui::port_open localhost "${REDIS_COMMANDER_PORT}"; then
    echo "[*] Redis Commander already running (PID $(cat "${DBUI_REDIS_COMMANDER_PID_FILE}"))."
    return 0
  fi

  if ! command -v redis-commander >/dev/null 2>&1; then
    echo "[!] redis-commander not installed; cannot start Redis UI." >&2
    return 1
  fi

  local redis_port="${REDIS_PORT:-6379}"
  local redis_password="${REDIS_PASSWORD:-admin}"
  echo "[*] Starting Redis Commander on $(common::ui_url "${REDIS_COMMANDER_PORT}" "/")..."
  local redis_cmd=(
    redis-commander
    --address 0.0.0.0
    --port "${REDIS_COMMANDER_PORT}"
    --redis-host localhost
    --redis-port "${redis_port}"
    --nosave
  )
  if [[ -n "${redis_password}" ]]; then
    redis_cmd+=(--redis-password "${redis_password}")
  fi
  nohup "${redis_cmd[@]}" \
    > "${DBUI_REDIS_COMMANDER_LOG_FILE}" 2>&1 &
  echo $! > "${DBUI_REDIS_COMMANDER_PID_FILE}"
  if ! dbui::wait_for_port localhost "${REDIS_COMMANDER_PORT}"; then
    echo "[!] Redis Commander failed to open port ${REDIS_COMMANDER_PORT}; see ${DBUI_REDIS_COMMANDER_LOG_FILE}" >&2
    return 1
  fi
  echo "[+] Redis Commander started (PID $(cat "${DBUI_REDIS_COMMANDER_PID_FILE}"))."
}

dbui::start() {
  dbui::ensure_dirs
  if ! dbui::port_open localhost "${POSTGRES_PORT:-5432}"; then
    echo "[*] PostgreSQL is not running on ${POSTGRES_PORT:-5432}. Start it with option 7 or 10."
  fi
  if ! dbui::port_open localhost "${MONGO_PORT:-27017}"; then
    echo "[*] MongoDB is not running on ${MONGO_PORT:-27017}. Start it with option 8 or 10."
  fi
  if ! dbui::port_open localhost "${REDIS_PORT:-6379}"; then
    echo "[*] Redis is not running on ${REDIS_PORT:-6379}. Start it with option 9 or 10."
  fi
  dbui::start_adminer
  dbui::start_mongo_express
  dbui::start_redis_commander
  echo "[+] Database UIs started."
}

dbui::stop_one() {
  local pid_file="$1"
  if dbui::pid_alive "${pid_file}"; then
    kill "$(cat "${pid_file}")" 2>/dev/null || true
  fi
  rm -f "${pid_file}"
}

dbui::stop() {
  dbui::stop_one "${DBUI_ADMINER_PID_FILE}"
  dbui::stop_one "${DBUI_MONGO_EXPRESS_PID_FILE}"
  dbui::stop_one "${DBUI_REDIS_COMMANDER_PID_FILE}"
  echo "[+] Database UIs stopped."
}

dbui::status_line() {
  local name="$1"
  local pid_file="$2"
  local port="$3"
  if dbui::pid_alive "${pid_file}" && dbui::port_open localhost "${port}"; then
    echo "[+] ${name}: $(common::ui_url "${port}" "/")"
  else
    echo "[-] ${name}: not running"
  fi
}

dbui::status() {
  dbui::status_line "Adminer" "${DBUI_ADMINER_PID_FILE}" "${ADMINER_PORT}"
  dbui::status_line "Mongo Express" "${DBUI_MONGO_EXPRESS_PID_FILE}" "${MONGO_EXPRESS_PORT}"
  dbui::status_line "Redis Commander" "${DBUI_REDIS_COMMANDER_PID_FILE}" "${REDIS_COMMANDER_PORT}"
}
