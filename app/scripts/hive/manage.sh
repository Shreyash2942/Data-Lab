#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"
source "${SCRIPT_DIR}/../hadoop/manage.sh"

HIVE_HS2_LOG_FILE="${HIVE_LOG_DIR}/hiveserver2-http.log"
HIVE_HS2_PID_FILE="${HIVE_PID_DIR}/hiveserver2-http.pid"
HIVE_SCRIPTS_DIR="${WORKSPACE}/app/scripts/hive"
HIVE_BEELINE_CLI="${HIVE_SCRIPTS_DIR}/cli.sh"

hive::ensure_dirs() {
  mkdir -p \
    "${HIVE_LOG_DIR}" \
    "${HIVE_PID_DIR}" \
    "${HIVE_METASTORE_DB}" \
    "${HIVE_WAREHOUSE}" \
    "${RUNTIME_ROOT}/hive/tmp"
}

hive::init_metastore_if_needed() {
  if [ ! -f "${HIVE_METASTORE_DB}/service.properties" ]; then
    echo "[*] Initializing Hive metastore (Derby)..."
    if ! "${SCHEMATOOL_BIN}" -dbType derby -initSchema; then
      echo "[!] Hive metastore initialization failed; cleaning and retrying once..."
      rm -rf "${HIVE_METASTORE_DB}" "${RUNTIME_ROOT}/hive/tmp"/*
      if ! "${SCHEMATOOL_BIN}" -dbType derby -initSchema; then
        echo "[!] Hive metastore initialization still failing. Check ${HIVE_METASTORE_DB} manually."
        return 1
      fi
    fi
  fi
}

hive::wait_for_port() {
  local host="$1" port="$2"
  HS2_WAIT_HOST="${host}" HS2_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys, time
host = os.environ["HS2_WAIT_HOST"]
port = int(os.environ["HS2_WAIT_PORT"])
deadline = time.time() + 60
while time.time() < deadline:
    s = socket.socket()
    s.settimeout(2)
    try:
        s.connect((host, port))
    except OSError:
        time.sleep(1)
    else:
        s.close()
        sys.exit(0)
print(f"[!] HiveServer2 did not open {host}:{port} within 60s", file=sys.stderr)
sys.exit(1)
PY
}

hive::port_open() {
  local host="$1" port="$2"
  HS2_WAIT_HOST="${host}" HS2_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["HS2_WAIT_HOST"]
port = int(os.environ["HS2_WAIT_PORT"])
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

hive::cleanup_stale_hs2() {
  if [[ -f "${HIVE_HS2_PID_FILE}" ]] && ! kill -0 "$(cat "${HIVE_HS2_PID_FILE}")" 2>/dev/null; then
    rm -f "${HIVE_HS2_PID_FILE}"
  fi

  if pgrep -f "hive.*hiveserver2" >/dev/null 2>&1; then
    if ! hive::port_open localhost "${HIVE_SERVER2_HTTP_PORT}"; then
      echo "[*] Removing stale HiveServer2 processes..."
      pkill -f "hive.*hiveserver2" || true
      sleep 1
      rm -f "${HIVE_HS2_PID_FILE}"
    fi
  fi
}

hive::hs2_running() {
  [[ -f "${HIVE_HS2_PID_FILE}" ]] && kill -0 "$(cat "${HIVE_HS2_PID_FILE}")" 2>/dev/null
}

hive::start_hs2() {
  hive::cleanup_stale_hs2

  if hive::hs2_running; then
    if hive::port_open localhost "${HIVE_SERVER2_HTTP_PORT}"; then
      echo "[*] HiveServer2 already running (PID $(cat "${HIVE_HS2_PID_FILE}"))."
      return
    fi
    echo "[*] HiveServer2 PID detected but port ${HIVE_SERVER2_HTTP_PORT} is closed; restarting..."
    hive::stop_hs2 || true
  fi

  echo "[*] Starting HiveServer2 (HTTP) on 0.0.0.0:${HIVE_SERVER2_HTTP_PORT}/${HIVE_SERVER2_HTTP_PATH}..."
  HIVE_CONF_DIR="${HIVE_HOME}/conf" \
  HADOOP_CONF_DIR="${HADOOP_HOME}/etc/hadoop" \
  HIVE_LOG_DIR="${HIVE_LOG_DIR}" \
  HIVESERVER2_PID_DIR="${HIVE_PID_DIR}" \
  JAVA_HOME=${JAVA_HOME} \
    nohup "${HIVE_HOME}/bin/hiveserver2" \
      --hiveconf hive.server2.authentication=NOSASL \
      --hiveconf hive.server2.transport.mode=http \
      --hiveconf hive.server2.thrift.http.port="${HIVE_SERVER2_HTTP_PORT}" \
      --hiveconf hive.server2.thrift.http.path="${HIVE_SERVER2_HTTP_PATH}" \
      --hiveconf hive.server2.thrift.bind.host=0.0.0.0 \
      > "${HIVE_HS2_LOG_FILE}" 2>&1 &
  echo $! > "${HIVE_HS2_PID_FILE}"
  if ! hive::wait_for_port localhost "${HIVE_SERVER2_HTTP_PORT}"; then
    echo "[!] HiveServer2 failed to open port ${HIVE_SERVER2_HTTP_PORT}. Recent log lines:" >&2
    tail -n 40 "${HIVE_HS2_LOG_FILE}" >&2 || true
    return 1
  fi
  echo "[+] HiveServer2 listening (log: ${HIVE_HS2_LOG_FILE})."
}

hive::stop_hs2() {
  if ! hive::hs2_running; then
    echo "[*] HiveServer2 is not running."
    return
  fi
  echo "[*] Stopping HiveServer2..."
  kill "$(cat "${HIVE_HS2_PID_FILE}")" 2>/dev/null || true
  rm -f "${HIVE_HS2_PID_FILE}"
}

hive::stop() {
  hive::stop_hs2
}

hive::verify_query() {
  if ! HIVE_CLI_SKIP_RC=1 bash "${HIVE_BEELINE_CLI}" -e 'SHOW DATABASES;' >/dev/null; then
    echo "[!] Verification query failed. Check ${HIVE_HS2_LOG_FILE} for details." >&2
    return 1
  fi
}

hive::prepare_cli() {
  hadoop::ensure_running
  hive::ensure_dirs
  hive::init_metastore_if_needed
  hive::start_hs2
  hive::verify_query || true
  cat <<'EOF'
[+] Hive CLI ready.
Run either helper:
  bash ~/app/scripts/hive/legacy_cli.sh   # classic CLI prompt
  bash ~/app/scripts/hive/cli.sh          # beeline wrapper

Spark SQL entrypoint:
  spark-sql -e 'SHOW DATABASES;'
EOF
}
