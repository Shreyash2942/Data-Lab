#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"
source "${SCRIPT_DIR}/../hadoop/manage.sh"

HIVE_HS2_LOG_FILE="${HIVE_LOG_DIR}/hiveserver2-http.log"
# Hive writes both http and legacy PID files; manage both to avoid stale blocks.
HIVE_HS2_HTTP_PID_FILE="${HIVE_PID_DIR}/hiveserver2-http.pid"
HIVE_HS2_LEGACY_PID_FILE="${HIVE_PID_DIR}/hiveserver2.pid"
HIVE_METASTORE_PORT="${HIVE_METASTORE_PORT:-9083}"
HIVE_METASTORE_LOG_FILE="${HIVE_LOG_DIR}/metastore.log"
HIVE_METASTORE_PID_FILE="${HIVE_PID_DIR}/metastore.pid"
HIVE_SCRIPTS_DIR="${WORKSPACE}/app/tech/hive"
HIVE_BEELINE_CLI="${HIVE_SCRIPTS_DIR}/cli.sh"
HIVE_AUX_JARS_PATH_DEFAULT=""
for jar in \
  "/opt/spark/jars/hudi-spark-bundle.jar" \
  "/opt/spark/jars/iceberg-spark-runtime.jar" \
  "/opt/spark/jars/delta-spark.jar" \
  "/opt/spark/jars/delta-storage.jar"; do
  if [[ -f "${jar}" ]]; then
    if [[ -z "${HIVE_AUX_JARS_PATH_DEFAULT}" ]]; then
      HIVE_AUX_JARS_PATH_DEFAULT="${jar}"
    else
      HIVE_AUX_JARS_PATH_DEFAULT="${HIVE_AUX_JARS_PATH_DEFAULT},${jar}"
    fi
  fi
done
: "${HIVE_AUX_JARS_PATH:=${HIVE_AUX_JARS_PATH_DEFAULT}}"

hive::ensure_dirs() {
  mkdir -p \
    "${HIVE_LOG_DIR}" \
    "${HIVE_PID_DIR}" \
    "${HIVE_METASTORE_DB}" \
    "${HIVE_WAREHOUSE}" \
    "${RUNTIME_ROOT}/hive/tmp"
}

hive::aux_jars_args() {
  if [[ -n "${HIVE_AUX_JARS_PATH}" ]]; then
    printf '%s\n' "${HIVE_AUX_JARS_PATH}"
  fi
}

hive::ensure_hdfs_paths() {
  # Keep Hive paths aligned with hive-site.xml defaults.
  "${HDFS_BIN}" dfs -mkdir -p /tmp /tmp/hive /hive /hive/warehouse
  "${HDFS_BIN}" dfs -chmod 1777 /tmp /tmp/hive
  "${HDFS_BIN}" dfs -chmod 775 /hive /hive/warehouse
  "${HDFS_BIN}" dfs -chown -R datalab:supergroup /hive /tmp/hive || true
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
deadline = time.time() + 120
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
print(f"[!] {os.environ.get('HS2_WAIT_SERVICE', 'service')} did not open {host}:{port} within 120s", file=sys.stderr)
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
  local pidfile
  for pidfile in "${HIVE_HS2_HTTP_PID_FILE}" "${HIVE_HS2_LEGACY_PID_FILE}"; do
    if [[ -f "${pidfile}" ]] && ! kill -0 "$(cat "${pidfile}")" 2>/dev/null; then
      rm -f "${pidfile}"
    fi
  done

  if pgrep -f "hive.*hiveserver2" >/dev/null 2>&1; then
    if ! hive::port_open localhost "${HIVE_SERVER2_HTTP_PORT}"; then
      echo "[*] Removing stale HiveServer2 processes..."
      pkill -f "hive.*hiveserver2" || true
      sleep 1
      rm -f "${HIVE_HS2_HTTP_PID_FILE}" "${HIVE_HS2_LEGACY_PID_FILE}"
    fi
  fi
}

hive::cleanup_stale_metastore() {
  if [[ -f "${HIVE_METASTORE_PID_FILE}" ]] && ! kill -0 "$(cat "${HIVE_METASTORE_PID_FILE}")" 2>/dev/null; then
    rm -f "${HIVE_METASTORE_PID_FILE}"
  fi

  if pgrep -f "HiveMetaStore" >/dev/null 2>&1; then
    if ! hive::port_open localhost "${HIVE_METASTORE_PORT}"; then
      echo "[*] Removing stale Hive metastore processes..."
      pkill -f "HiveMetaStore" || true
      sleep 1
      rm -f "${HIVE_METASTORE_PID_FILE}"
    fi
  fi
}

hive::metastore_running() {
  if hive::port_open localhost "${HIVE_METASTORE_PORT}"; then
    return 0
  fi
  if [[ -f "${HIVE_METASTORE_PID_FILE}" ]] && kill -0 "$(cat "${HIVE_METASTORE_PID_FILE}")" 2>/dev/null; then
    return 0
  fi
  return 1
}

hive::start_metastore() {
  hive::cleanup_stale_metastore

  if hive::metastore_running; then
    if hive::port_open localhost "${HIVE_METASTORE_PORT}"; then
      local running_pid="<unknown>"
      if [[ -f "${HIVE_METASTORE_PID_FILE}" ]]; then
        running_pid="$(cat "${HIVE_METASTORE_PID_FILE}")"
      fi
      echo "[*] Hive metastore already running (PID ${running_pid})."
      return
    fi
    echo "[*] Hive metastore PID detected but port ${HIVE_METASTORE_PORT} is closed; restarting..."
    hive::stop_metastore || true
  fi

  echo "[*] Starting Hive metastore (Thrift) on 0.0.0.0:${HIVE_METASTORE_PORT}..."
  HIVE_CONF_DIR="${HIVE_HOME}/conf" \
  HADOOP_CONF_DIR="${HADOOP_HOME}/etc/hadoop" \
  HIVE_AUX_JARS_PATH="${HIVE_AUX_JARS_PATH}" \
  HIVE_LOG_DIR="${HIVE_LOG_DIR}" \
  METASTORE_PID_DIR="${HIVE_PID_DIR}" \
  JAVA_HOME="${JAVA_HOME}" \
    nohup "${HIVE_HOME}/bin/hive" --service metastore -p "${HIVE_METASTORE_PORT}" \
      > "${HIVE_METASTORE_LOG_FILE}" 2>&1 &
  echo $! > "${HIVE_METASTORE_PID_FILE}"

  HS2_WAIT_SERVICE="Hive metastore" hive::wait_for_port localhost "${HIVE_METASTORE_PORT}" "Hive metastore" || {
    echo "[!] Hive metastore failed to open port ${HIVE_METASTORE_PORT}. Recent log lines:" >&2
    tail -n 40 "${HIVE_METASTORE_LOG_FILE}" >&2 || true
    return 1
  }
  echo "[+] Hive metastore listening (log: ${HIVE_METASTORE_LOG_FILE})."
}

hive::hs2_running() {
  if [[ -f "${HIVE_HS2_HTTP_PID_FILE}" ]] && kill -0 "$(cat "${HIVE_HS2_HTTP_PID_FILE}")" 2>/dev/null; then
    return 0
  fi
  [[ -f "${HIVE_HS2_LEGACY_PID_FILE}" ]] && kill -0 "$(cat "${HIVE_HS2_LEGACY_PID_FILE}")" 2>/dev/null
}

hive::start_hs2() {
  hive::cleanup_stale_hs2
  if ! hive::port_open localhost "${HIVE_METASTORE_PORT}"; then
    hive::start_metastore
  fi

  if hive::hs2_running; then
    if hive::port_open localhost "${HIVE_SERVER2_HTTP_PORT}"; then
      local running_pid="<unknown>"
      if [[ -f "${HIVE_HS2_HTTP_PID_FILE}" ]]; then
        running_pid="$(cat "${HIVE_HS2_HTTP_PID_FILE}")"
      elif [[ -f "${HIVE_HS2_LEGACY_PID_FILE}" ]]; then
        running_pid="$(cat "${HIVE_HS2_LEGACY_PID_FILE}")"
      fi
      echo "[*] HiveServer2 already running (PID ${running_pid})."
      return
    fi
    echo "[*] HiveServer2 PID detected but port ${HIVE_SERVER2_HTTP_PORT} is closed; restarting..."
    hive::stop_hs2 || true
  fi

  echo "[*] Starting HiveServer2 (HTTP) on 0.0.0.0:${HIVE_SERVER2_HTTP_PORT}/${HIVE_SERVER2_HTTP_PATH}..."
  HIVE_CONF_DIR="${HIVE_HOME}/conf" \
  HADOOP_CONF_DIR="${HADOOP_HOME}/etc/hadoop" \
  HIVE_AUX_JARS_PATH="${HIVE_AUX_JARS_PATH}" \
  HIVE_LOG_DIR="${HIVE_LOG_DIR}" \
  HIVESERVER2_PID_DIR="${HIVE_PID_DIR}" \
  JAVA_HOME=${JAVA_HOME} \
    nohup "${HIVE_HOME}/bin/hiveserver2" \
      --hiveconf hive.server2.authentication=NOSASL \
      --hiveconf hive.server2.transport.mode=http \
      --hiveconf hive.server2.thrift.http.port="${HIVE_SERVER2_HTTP_PORT}" \
      --hiveconf hive.server2.thrift.http.path="${HIVE_SERVER2_HTTP_PATH}" \
      --hiveconf hive.notification.event.poll.interval=0 \
      --hiveconf hive.server2.thrift.bind.host=0.0.0.0 \
      --hiveconf hive.aux.jars.path="${HIVE_AUX_JARS_PATH}" \
      > "${HIVE_HS2_LOG_FILE}" 2>&1 &
  echo $! > "${HIVE_HS2_HTTP_PID_FILE}"
  if ! HS2_WAIT_SERVICE="HiveServer2" hive::wait_for_port localhost "${HIVE_SERVER2_HTTP_PORT}" "HiveServer2"; then
    echo "[!] HiveServer2 failed to open port ${HIVE_SERVER2_HTTP_PORT}. Recent log lines:" >&2
    tail -n 40 "${HIVE_HS2_LOG_FILE}" >&2 || true
    return 1
  fi
  echo "[+] HiveServer2 listening (log: ${HIVE_HS2_LOG_FILE})."
  # Remove stale legacy PID file if Hive created it (Hive writes both names on some versions).
  if [[ -f "${HIVE_HS2_LEGACY_PID_FILE}" ]] && ! kill -0 "$(cat "${HIVE_HS2_LEGACY_PID_FILE}")" 2>/dev/null; then
    rm -f "${HIVE_HS2_LEGACY_PID_FILE}"
  fi
}

hive::stop_hs2() {
  if ! hive::hs2_running; then
    echo "[*] HiveServer2 is not running."
    return
  fi
  echo "[*] Stopping HiveServer2..."
  # Prefer the HTTP PID file, fall back to legacy if needed.
  local pid=""; local pidfile=""
  for pidfile in "${HIVE_HS2_HTTP_PID_FILE}" "${HIVE_HS2_LEGACY_PID_FILE}"; do
    if [[ -f "${pidfile}" ]]; then
      pid="$(cat "${pidfile}")"
      break
    fi
  done
  if [[ -n "${pid}" ]]; then
    kill "${pid}" 2>/dev/null || true
  fi
  rm -f "${HIVE_HS2_HTTP_PID_FILE}" "${HIVE_HS2_LEGACY_PID_FILE}"
}

hive::stop_metastore() {
  if ! hive::metastore_running; then
    echo "[*] Hive metastore is not running."
    return
  fi
  echo "[*] Stopping Hive metastore..."
  local pid=""
  if [[ -f "${HIVE_METASTORE_PID_FILE}" ]]; then
    pid="$(cat "${HIVE_METASTORE_PID_FILE}")"
  fi
  if [[ -n "${pid}" ]]; then
    kill "${pid}" 2>/dev/null || true
  fi
  pkill -f "HiveMetaStore" 2>/dev/null || true
  rm -f "${HIVE_METASTORE_PID_FILE}"
}

hive::stop() {
  hive::stop_hs2
  hive::stop_metastore
}

hive::verify_query() {
  if ! HIVE_CLI_SKIP_RC=1 bash "${HIVE_BEELINE_CLI}" -e 'SHOW DATABASES;' >/dev/null; then
    echo "[!] Verification query failed. Check ${HIVE_HS2_LOG_FILE} for details." >&2
    return 1
  fi
}

hive::prepare_cli() {
  hadoop::ensure_running
  hive::ensure_hdfs_paths
  hive::ensure_dirs
  hive::init_metastore_if_needed
  hive::start_metastore
  hive::start_hs2
  hive::verify_query || true
  cat <<'EOF'
[+] Hive CLI ready.
Run either helper:
  hive        # classic Hive CLI prompt
  hivecli     # classic Hive CLI prompt
  hivebeeline # Beeline wrapper (HS2 HTTP)

Spark SQL entrypoint:
  spark-sql -e 'SHOW DATABASES;'
EOF
}
