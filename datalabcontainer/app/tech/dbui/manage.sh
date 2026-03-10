#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

DBUI_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DBUI_SCRIPT_DIR}/../common.sh"

DBUI_BASE="${RUNTIME_ROOT}/dbui"
DBUI_LOG_DIR="${DBUI_BASE}/logs"
DBUI_PID_DIR="${DBUI_BASE}/pids"
MONGO_EXPRESS_PID_FILE="${DBUI_PID_DIR}/mongo-express.pid"
REDIS_COMMANDER_PID_FILE="${DBUI_PID_DIR}/redis-commander.pid"
MONGO_EXPRESS_LOG_FILE="${DBUI_LOG_DIR}/mongo-express.log"
REDIS_COMMANDER_LOG_FILE="${DBUI_LOG_DIR}/redis-commander.log"
DBUI_NODE_MODULES="${DBUI_BASE}/node_modules"
DBUI_PREBUILT_BASE="${DBUI_PREBUILT_BASE:-/opt/dbui}"
DBUI_PREBUILT_NODE_MODULES="${DBUI_PREBUILT_BASE}/node_modules"
MONGO_EXPRESS_RUNTIME_BIN="${DBUI_NODE_MODULES}/.bin/mongo-express"
REDIS_COMMANDER_RUNTIME_BIN="${DBUI_NODE_MODULES}/.bin/redis-commander"
MONGO_EXPRESS_PREBUILT_BIN="${DBUI_PREBUILT_NODE_MODULES}/.bin/mongo-express"
REDIS_COMMANDER_PREBUILT_BIN="${DBUI_PREBUILT_NODE_MODULES}/.bin/redis-commander"
MONGO_EXPRESS_BIN="${MONGO_EXPRESS_RUNTIME_BIN}"
REDIS_COMMANDER_BIN="${REDIS_COMMANDER_RUNTIME_BIN}"
# 1.0.2+ can pull unsupported patch:/github deps in plain npm installs.
MONGO_EXPRESS_NPM_VERSION="${MONGO_EXPRESS_NPM_VERSION:-1.0.0}"
REDIS_COMMANDER_NPM_VERSION="${REDIS_COMMANDER_NPM_VERSION:-0.9.0}"

: "${MONGO_PORT:=27017}"
: "${MONGO_DB:=datalab}"
: "${MONGO_ROOT_USERNAME:=admin}"
: "${MONGO_ROOT_PASSWORD:=admin}"
: "${MONGO_EXPRESS_PORT:=8083}"
: "${MONGO_EXPRESS_BASICAUTH:=false}"
: "${MONGO_EXPRESS_USERNAME:=admin}"
: "${MONGO_EXPRESS_PASSWORD:=admin}"
: "${REDIS_PORT:=6379}"
: "${REDIS_PASSWORD:=admin}"
: "${REDIS_COMMANDER_PORT:=8084}"

MONGO_PORT="$(strip_cr "${MONGO_PORT}")"
MONGO_DB="$(strip_cr "${MONGO_DB}")"
MONGO_ROOT_USERNAME="$(strip_cr "${MONGO_ROOT_USERNAME}")"
MONGO_ROOT_PASSWORD="$(strip_cr "${MONGO_ROOT_PASSWORD}")"
MONGO_EXPRESS_PORT="$(strip_cr "${MONGO_EXPRESS_PORT}")"
MONGO_EXPRESS_BASICAUTH="$(strip_cr "${MONGO_EXPRESS_BASICAUTH}")"
MONGO_EXPRESS_USERNAME="$(strip_cr "${MONGO_EXPRESS_USERNAME}")"
MONGO_EXPRESS_PASSWORD="$(strip_cr "${MONGO_EXPRESS_PASSWORD}")"
REDIS_PORT="$(strip_cr "${REDIS_PORT}")"
REDIS_PASSWORD="$(strip_cr "${REDIS_PASSWORD}")"
REDIS_COMMANDER_PORT="$(strip_cr "${REDIS_COMMANDER_PORT}")"

dbui::ensure_dirs() {
  mkdir -p "${DBUI_BASE}" "${DBUI_LOG_DIR}" "${DBUI_PID_DIR}"
}

dbui::port_open() {
  local host="$1" port="$2"
  DBUI_WAIT_HOST="${host}" DBUI_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["DBUI_WAIT_HOST"]
port = int(os.environ["DBUI_WAIT_PORT"])
for family, socktype, proto, _, sockaddr in socket.getaddrinfo(host, port, socket.AF_UNSPEC, socket.SOCK_STREAM):
    s = socket.socket(family, socktype, proto)
    s.settimeout(1)
    try:
        s.connect(sockaddr)
    except OSError:
        pass
    else:
        s.close()
        sys.exit(0)
    finally:
        try:
            s.close()
        except OSError:
            pass
sys.exit(1)
PY
}

dbui::port_listening() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :${port}" 2>/dev/null | awk 'NR>1 { found=1 } END { exit (found ? 0 : 1) }'
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk -v p=":${port}" '$4 ~ p"$" { found=1 } END { exit (found ? 0 : 1) }'
    return $?
  fi
  return 1
}

dbui::wait_for_port() {
  local host="$1" port="$2"
  local deadline=$((SECONDS + 30))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if dbui::port_open "${host}" "${port}" || dbui::port_listening "${port}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

dbui::pid_alive() {
  local pid_file="$1" pid=""
  [[ -f "${pid_file}" ]] || return 1
  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

dbui::cleanup_stale_pid() {
  local pid_file="$1"
  if [[ -f "${pid_file}" ]] && ! dbui::pid_alive "${pid_file}"; then
    rm -f "${pid_file}"
  fi
}

dbui::npm_bin() {
  if command -v npm >/dev/null 2>&1; then
    command -v npm
    return 0
  fi
  echo "[!] npm not found; cannot install Mongo Express / Redis Commander." >&2
  return 1
}

dbui::read_package_version() {
  local package_json="$1"
  [[ -f "${package_json}" ]] || return 1
  awk -F'"' '/"version"/ { print $4; exit }' "${package_json}" 2>/dev/null || true
}

dbui::runtime_packages_ready() {
  local installed_mongo_version="" installed_redis_version=""
  installed_mongo_version="$(dbui::read_package_version "${DBUI_NODE_MODULES}/mongo-express/package.json" || true)"
  installed_redis_version="$(dbui::read_package_version "${DBUI_NODE_MODULES}/redis-commander/package.json" || true)"
  [[ -x "${MONGO_EXPRESS_RUNTIME_BIN}" ]] && [[ -x "${REDIS_COMMANDER_RUNTIME_BIN}" ]] && \
    [[ "${installed_mongo_version}" == "${MONGO_EXPRESS_NPM_VERSION}" ]] && \
    [[ "${installed_redis_version}" == "${REDIS_COMMANDER_NPM_VERSION}" ]]
}

dbui::prebuilt_packages_ready() {
  local installed_mongo_version="" installed_redis_version=""
  installed_mongo_version="$(dbui::read_package_version "${DBUI_PREBUILT_NODE_MODULES}/mongo-express/package.json" || true)"
  installed_redis_version="$(dbui::read_package_version "${DBUI_PREBUILT_NODE_MODULES}/redis-commander/package.json" || true)"
  [[ -x "${MONGO_EXPRESS_PREBUILT_BIN}" ]] && [[ -x "${REDIS_COMMANDER_PREBUILT_BIN}" ]] && \
    [[ "${installed_mongo_version}" == "${MONGO_EXPRESS_NPM_VERSION}" ]] && \
    [[ "${installed_redis_version}" == "${REDIS_COMMANDER_NPM_VERSION}" ]]
}

dbui::ensure_node_packages() {
  local npm_bin
  MONGO_EXPRESS_BIN="${MONGO_EXPRESS_RUNTIME_BIN}"
  REDIS_COMMANDER_BIN="${REDIS_COMMANDER_RUNTIME_BIN}"

  if dbui::runtime_packages_ready; then
    return 0
  fi

  if dbui::prebuilt_packages_ready; then
    MONGO_EXPRESS_BIN="${MONGO_EXPRESS_PREBUILT_BIN}"
    REDIS_COMMANDER_BIN="${REDIS_COMMANDER_PREBUILT_BIN}"
    return 0
  fi

  npm_bin="$(dbui::npm_bin)"
  echo "[*] Installing DB UI packages (mongo-express@${MONGO_EXPRESS_NPM_VERSION}, redis-commander@${REDIS_COMMANDER_NPM_VERSION})..."
  rm -rf "${DBUI_NODE_MODULES}" "${DBUI_BASE}/package-lock.json" "${DBUI_BASE}/package.json"
  "${npm_bin}" install \
    --prefix "${DBUI_BASE}" \
    --no-save \
    --no-audit \
    --no-fund \
    --loglevel=error \
    "mongo-express@${MONGO_EXPRESS_NPM_VERSION}" \
    "redis-commander@${REDIS_COMMANDER_NPM_VERSION}"
  MONGO_EXPRESS_BIN="${MONGO_EXPRESS_RUNTIME_BIN}"
  REDIS_COMMANDER_BIN="${REDIS_COMMANDER_RUNTIME_BIN}"
}

dbui::start_mongo_express() {
  dbui::cleanup_stale_pid "${MONGO_EXPRESS_PID_FILE}"
  if dbui::pid_alive "${MONGO_EXPRESS_PID_FILE}" && (dbui::port_open localhost "${MONGO_EXPRESS_PORT}" || dbui::port_listening "${MONGO_EXPRESS_PORT}"); then
    echo "[*] Mongo Express already running (PID $(cat "${MONGO_EXPRESS_PID_FILE}"))."
    return 0
  fi
  if dbui::port_open localhost "${MONGO_EXPRESS_PORT}" || dbui::port_listening "${MONGO_EXPRESS_PORT}"; then
    echo "[*] Mongo Express already running on port ${MONGO_EXPRESS_PORT}."
    return 0
  fi

  dbui::ensure_node_packages
  local mongo_url
  mongo_url="mongodb://${MONGO_ROOT_USERNAME}:${MONGO_ROOT_PASSWORD}@127.0.0.1:${MONGO_PORT}/${MONGO_DB}?authSource=admin"

  echo "[*] Starting Mongo Express on $(common::ui_url "${MONGO_EXPRESS_PORT}" "/")..."
  (
    # mongo-express v1.x reads host from VCAP_APP_HOST in config.default.js.
    export HOST="0.0.0.0"
    export VCAP_APP_HOST="0.0.0.0"
    export ME_CONFIG_SITE_HOST="0.0.0.0"
    export PORT="${MONGO_EXPRESS_PORT}"
    export ME_CONFIG_MONGODB_ENABLE_ADMIN="true"
    export ME_CONFIG_MONGODB_URL="${mongo_url}"
    export ME_CONFIG_BASICAUTH="${MONGO_EXPRESS_BASICAUTH}"
    export ME_CONFIG_BASICAUTH_USERNAME="${MONGO_EXPRESS_USERNAME}"
    export ME_CONFIG_BASICAUTH_PASSWORD="${MONGO_EXPRESS_PASSWORD}"
    nohup "${MONGO_EXPRESS_BIN}" > "${MONGO_EXPRESS_LOG_FILE}" 2>&1 &
    echo $! > "${MONGO_EXPRESS_PID_FILE}"
  )

  if ! dbui::wait_for_port localhost "${MONGO_EXPRESS_PORT}"; then
    echo "[!] Mongo Express failed to open port ${MONGO_EXPRESS_PORT}; see ${MONGO_EXPRESS_LOG_FILE}" >&2
    tail -n 60 "${MONGO_EXPRESS_LOG_FILE}" >&2 || true
    return 1
  fi
  if ! dbui::pid_alive "${MONGO_EXPRESS_PID_FILE}"; then
    echo "[!] Mongo Express process exited unexpectedly; see ${MONGO_EXPRESS_LOG_FILE}" >&2
    tail -n 60 "${MONGO_EXPRESS_LOG_FILE}" >&2 || true
    return 1
  fi
  echo "[+] Mongo Express started (PID $(cat "${MONGO_EXPRESS_PID_FILE}"))."
}

dbui::start_redis_commander() {
  dbui::cleanup_stale_pid "${REDIS_COMMANDER_PID_FILE}"
  if dbui::pid_alive "${REDIS_COMMANDER_PID_FILE}" && (dbui::port_open localhost "${REDIS_COMMANDER_PORT}" || dbui::port_listening "${REDIS_COMMANDER_PORT}"); then
    echo "[*] Redis Commander already running (PID $(cat "${REDIS_COMMANDER_PID_FILE}"))."
    return 0
  fi
  if dbui::port_open localhost "${REDIS_COMMANDER_PORT}" || dbui::port_listening "${REDIS_COMMANDER_PORT}"; then
    echo "[*] Redis Commander already running on port ${REDIS_COMMANDER_PORT}."
    return 0
  fi

  dbui::ensure_node_packages

  echo "[*] Starting Redis Commander on $(common::ui_url "${REDIS_COMMANDER_PORT}" "/")..."
  (
    nohup "${REDIS_COMMANDER_BIN}" \
      --address "0.0.0.0" \
      --port "${REDIS_COMMANDER_PORT}" \
      --redis-host "127.0.0.1" \
      --redis-port "${REDIS_PORT}" \
      --redis-password "${REDIS_PASSWORD}" \
      > "${REDIS_COMMANDER_LOG_FILE}" 2>&1 &
    echo $! > "${REDIS_COMMANDER_PID_FILE}"
  )

  if ! dbui::wait_for_port localhost "${REDIS_COMMANDER_PORT}"; then
    echo "[!] Redis Commander failed to open port ${REDIS_COMMANDER_PORT}; see ${REDIS_COMMANDER_LOG_FILE}" >&2
    tail -n 60 "${REDIS_COMMANDER_LOG_FILE}" >&2 || true
    return 1
  fi
  if ! dbui::pid_alive "${REDIS_COMMANDER_PID_FILE}"; then
    echo "[!] Redis Commander process exited unexpectedly; see ${REDIS_COMMANDER_LOG_FILE}" >&2
    tail -n 60 "${REDIS_COMMANDER_LOG_FILE}" >&2 || true
    return 1
  fi
  echo "[+] Redis Commander started (PID $(cat "${REDIS_COMMANDER_PID_FILE}"))."
}

dbui::start() {
  dbui::ensure_dirs
  dbui::start_mongo_express
  dbui::start_redis_commander
}

dbui::stop_mongo_express() {
  dbui::cleanup_stale_pid "${MONGO_EXPRESS_PID_FILE}"
  if dbui::pid_alive "${MONGO_EXPRESS_PID_FILE}"; then
    kill "$(cat "${MONGO_EXPRESS_PID_FILE}")" >/dev/null 2>&1 || true
  fi
  pkill -f "${MONGO_EXPRESS_RUNTIME_BIN}" >/dev/null 2>&1 || true
  pkill -f "${MONGO_EXPRESS_PREBUILT_BIN}" >/dev/null 2>&1 || true
  rm -f "${MONGO_EXPRESS_PID_FILE}"
  echo "[+] Mongo Express stopped."
}

dbui::stop_redis_commander() {
  dbui::cleanup_stale_pid "${REDIS_COMMANDER_PID_FILE}"
  if dbui::pid_alive "${REDIS_COMMANDER_PID_FILE}"; then
    kill "$(cat "${REDIS_COMMANDER_PID_FILE}")" >/dev/null 2>&1 || true
  fi
  pkill -f "${REDIS_COMMANDER_RUNTIME_BIN}" >/dev/null 2>&1 || true
  pkill -f "${REDIS_COMMANDER_PREBUILT_BIN}" >/dev/null 2>&1 || true
  rm -f "${REDIS_COMMANDER_PID_FILE}"
  echo "[+] Redis Commander stopped."
}

dbui::stop() {
  dbui::stop_redis_commander
  dbui::stop_mongo_express
}
