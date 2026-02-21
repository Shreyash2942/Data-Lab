#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

MONGODB_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${MONGODB_SCRIPT_DIR}/../common.sh"

if ! declare -F strip_cr >/dev/null; then
  strip_cr() {
    local value="${1:-}"
    value="${value//$'\r'/}"
    printf '%s' "${value}"
  }
fi

MONGODB_BASE="${RUNTIME_ROOT}/mongodb"
MONGODB_DATA_DIR="${MONGODB_BASE}/data"
MONGODB_LOG_DIR="${MONGODB_BASE}/logs"
MONGODB_PID_DIR="${MONGODB_BASE}/pids"
MONGODB_PID_FILE="${MONGODB_PID_DIR}/mongod.pid"
MONGODB_LOG_FILE="${MONGODB_LOG_DIR}/mongod.log"
MONGODB_AUTH_BOOTSTRAP_MARKER="${MONGODB_BASE}/.auth_bootstrapped"

: "${MONGO_PORT:=27017}"
: "${MONGO_DB:=datalab}"
: "${MONGO_ROOT_USERNAME:=admin}"
: "${MONGO_ROOT_PASSWORD:=admin}"
: "${MONGO_AUTH_ENABLED:=true}"
MONGO_PORT="$(strip_cr "${MONGO_PORT}")"
MONGO_DB="$(strip_cr "${MONGO_DB}")"
MONGO_ROOT_USERNAME="$(strip_cr "${MONGO_ROOT_USERNAME}")"
MONGO_ROOT_PASSWORD="$(strip_cr "${MONGO_ROOT_PASSWORD}")"
MONGO_AUTH_ENABLED="$(strip_cr "${MONGO_AUTH_ENABLED}")"

mongodb::mongod_bin() {
  if command -v mongod >/dev/null 2>&1; then
    command -v mongod
    return
  fi
  if [[ -x "/opt/mongodb/bin/mongod" ]]; then
    printf '%s\n' "/opt/mongodb/bin/mongod"
    return
  fi
  echo "[!] mongod binary not found." >&2
  return 1
}

MONGOD_BIN="$(mongodb::mongod_bin)"

mongodb::ensure_dirs() {
  mkdir -p "${MONGODB_DATA_DIR}" "${MONGODB_LOG_DIR}" "${MONGODB_PID_DIR}"
  if [[ "$(id -u)" -eq 0 ]]; then
    local app_user="${LAB_APP_USER:-datalab}"
    chown -R "${app_user}:${app_user}" "${MONGODB_BASE}" 2>/dev/null || true
    # On Windows bind mounts chown may be ignored; keep directories writable for datalab.
    chmod 777 "${MONGODB_BASE}" "${MONGODB_DATA_DIR}" "${MONGODB_LOG_DIR}" "${MONGODB_PID_DIR}" 2>/dev/null || true
    [[ -f "${MONGODB_PID_FILE}" ]] && chmod 666 "${MONGODB_PID_FILE}" 2>/dev/null || true
    [[ -f "${MONGODB_LOG_FILE}" ]] && chmod 666 "${MONGODB_LOG_FILE}" 2>/dev/null || true
  fi
}

mongodb::pid_alive() {
  [[ -f "${MONGODB_PID_FILE}" ]] && kill -0 "$(cat "${MONGODB_PID_FILE}")" 2>/dev/null
}

mongodb::cleanup_stale_pid() {
  if [[ -f "${MONGODB_PID_FILE}" ]] && ! mongodb::pid_alive; then
    rm -f "${MONGODB_PID_FILE}"
  fi
}

mongodb::port_open() {
  local host="$1" port="$2"
  MONGO_WAIT_HOST="${host}" MONGO_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["MONGO_WAIT_HOST"]
port = int(os.environ["MONGO_WAIT_PORT"])
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

mongodb::wait_for_port() {
  local deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if mongodb::port_open localhost "${MONGO_PORT}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

mongodb::bootstrap_auth() {
  MONGO_PORT="${MONGO_PORT}" \
  MONGO_DB="${MONGO_DB}" \
  MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME}" \
  MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD}" \
  python3 - <<'PY'
import os
from pymongo import MongoClient
from pymongo.errors import OperationFailure

port = int(os.environ["MONGO_PORT"])
db_name = os.environ["MONGO_DB"]
username = os.environ["MONGO_ROOT_USERNAME"]
password = os.environ["MONGO_ROOT_PASSWORD"]
uri = f"mongodb://127.0.0.1:{port}/admin?directConnection=true"

client = MongoClient(uri, serverSelectionTimeoutMS=5000)
admin = client["admin"]

def ensure_db():
    db = client[db_name]
    db["sample_collection"].update_one({"_id": "init"}, {"$set": {"initialized": True}}, upsert=True)

try:
    info = admin.command("usersInfo", username)
    if info.get("users"):
        ensure_db()
        raise SystemExit(0)
    admin.command(
        "createUser",
        username,
        pwd=password,
        roles=[{"role": "root", "db": "admin"}],
    )
    ensure_db()
except OperationFailure:
    # During bootstrap phase we run without auth; any failure here should bubble up.
    raise
PY
}

mongodb::ensure_configured_auth_user() {
  MONGO_PORT="${MONGO_PORT}" \
  MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME}" \
  MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD}" \
  python3 - <<'PY'
import os
from pymongo import MongoClient
from pymongo.errors import PyMongoError

port = int(os.environ["MONGO_PORT"])
target_user = os.environ["MONGO_ROOT_USERNAME"]
target_password = os.environ["MONGO_ROOT_PASSWORD"]

def connect(user, password):
    uri = f"mongodb://{user}:{password}@127.0.0.1:{port}/admin?authSource=admin&directConnection=true"
    client = MongoClient(uri, serverSelectionTimeoutMS=5000)
    client.admin.command("ping")
    return client

def ensure_target_user(client):
    admin = client["admin"]
    info = admin.command("usersInfo", target_user)
    if info.get("users"):
      admin.command("updateUser", target_user, pwd=target_password, roles=[{"role": "root", "db": "admin"}])
    else:
      admin.command("createUser", target_user, pwd=target_password, roles=[{"role": "root", "db": "admin"}])

try:
    # Already valid with configured credentials.
    client = connect(target_user, target_password)
    client.close()
    raise SystemExit(0)
except PyMongoError:
    pass

for fallback_user, fallback_password in [("datalab", "datalab"), ("admin", "admin")]:
    try:
        client = connect(fallback_user, fallback_password)
        ensure_target_user(client)
        client.close()
        raise SystemExit(0)
    except PyMongoError:
        continue

raise SystemExit("Could not authenticate with configured or fallback MongoDB credentials.")
PY
}

mongodb::shutdown() {
  "${MONGOD_BIN}" --dbpath "${MONGODB_DATA_DIR}" --shutdown >/dev/null 2>&1 || true
  if [[ -f "${MONGODB_PID_FILE}" ]]; then
    kill "$(cat "${MONGODB_PID_FILE}")" >/dev/null 2>&1 || true
  fi
  rm -f "${MONGODB_PID_FILE}"
}

mongodb::start() {
  mongodb::ensure_dirs
  mongodb::cleanup_stale_pid

  if mongodb::pid_alive && mongodb::port_open localhost "${MONGO_PORT}"; then
    if [[ "${MONGO_AUTH_ENABLED}" == "true" ]]; then
      mongodb::ensure_configured_auth_user
    fi
    echo "[*] MongoDB already running (PID $(cat "${MONGODB_PID_FILE}"))."
    return
  fi

  echo "[*] Starting MongoDB..."
  local base_args=(
    --dbpath "${MONGODB_DATA_DIR}"
    --bind_ip 0.0.0.0
    --port "${MONGO_PORT}"
    --logpath "${MONGODB_LOG_FILE}"
    --logappend
    --pidfilepath "${MONGODB_PID_FILE}"
    --fork
  )

  # First-time bootstrap: start without auth, create user, restart with auth.
  if [[ "${MONGO_AUTH_ENABLED}" == "true" && ! -f "${MONGODB_AUTH_BOOTSTRAP_MARKER}" ]]; then
    "${MONGOD_BIN}" "${base_args[@]}"
    if ! mongodb::wait_for_port; then
      echo "[!] MongoDB bootstrap instance failed to open port ${MONGO_PORT}." >&2
      tail -n 40 "${MONGODB_LOG_FILE}" >&2 || true
      return 1
    fi
    mongodb::bootstrap_auth
    touch "${MONGODB_AUTH_BOOTSTRAP_MARKER}"
    mongodb::shutdown
  fi

  local run_args=("${base_args[@]}")
  if [[ "${MONGO_AUTH_ENABLED}" == "true" ]]; then
    run_args+=(--auth)
  fi

  "${MONGOD_BIN}" "${run_args[@]}"
  if ! mongodb::wait_for_port; then
    echo "[!] MongoDB failed to open port ${MONGO_PORT}. Recent log lines:" >&2
    tail -n 40 "${MONGODB_LOG_FILE}" >&2 || true
    return 1
  fi

  if [[ "${MONGO_AUTH_ENABLED}" == "true" ]]; then
    mongodb::ensure_configured_auth_user
  fi

  echo "MongoDB listening on localhost:${MONGO_PORT} (db=${MONGO_DB}, auth=${MONGO_AUTH_ENABLED})"
}

mongodb::stop() {
  if [[ ! -f "${MONGODB_PID_FILE}" ]] && ! mongodb::port_open localhost "${MONGO_PORT}"; then
    echo "[*] MongoDB is not running."
    return 0
  fi

  echo "[*] Stopping MongoDB..."
  mongodb::shutdown
}
