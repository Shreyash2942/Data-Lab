#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

TRINO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TRINO_SCRIPT_DIR}/../common.sh"

TRINO_HOME="${TRINO_HOME:-/opt/trino}"
TRINO_RUNTIME_BASE="${RUNTIME_ROOT}/trino"
TRINO_ETC_DIR="${TRINO_RUNTIME_BASE}/etc"
TRINO_DATA_DIR="${TRINO_RUNTIME_BASE}/data"
TRINO_LOG_DIR="${TRINO_RUNTIME_BASE}/logs"
TRINO_PID_DIR="${TRINO_RUNTIME_BASE}/pids"
TRINO_TEMPLATE_ETC="${TRINO_TEMPLATE_ETC:-/opt/trino/etc-template}"
TRINO_JAVA_HOME="${TRINO_JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"

TRINO_PORT="${TRINO_PORT:-8091}"
TRINO_USER="${TRINO_USER:-trino}"
TRINO_PID_FILE="${TRINO_PID_DIR}/trino.pid"
TRINO_LOG_FILE="${TRINO_LOG_DIR}/trino.log"

trino::ensure_dirs() {
  mkdir -p "${TRINO_ETC_DIR}" "${TRINO_DATA_DIR}" "${TRINO_LOG_DIR}" "${TRINO_PID_DIR}"
  if [[ -d "${TRINO_TEMPLATE_ETC}" ]]; then
    cp -r "${TRINO_TEMPLATE_ETC}/." "${TRINO_ETC_DIR}/" 2>/dev/null || true
  fi
  if [[ -f "${TRINO_ETC_DIR}/node.properties" ]]; then
    sed -i "s|^node.data-dir=.*$|node.data-dir=${TRINO_DATA_DIR}|" "${TRINO_ETC_DIR}/node.properties" || true
    sed -i "s|^node.id=.*$|node.id=trino-$(hostname)|" "${TRINO_ETC_DIR}/node.properties" || true
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    local app_user="${LAB_APP_USER:-datalab}"
    chown -R "${app_user}:${app_user}" "${TRINO_RUNTIME_BASE}" 2>/dev/null || true
    chmod -R u+rwX,go+rX "${TRINO_RUNTIME_BASE}" 2>/dev/null || true
  fi
}

trino::pid_alive() {
  [[ -f "${TRINO_PID_FILE}" ]] && kill -0 "$(cat "${TRINO_PID_FILE}")" 2>/dev/null
}

trino::port_open() {
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

trino::wait_for_port() {
  local host="$1" port="$2" deadline
  deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if trino::port_open "${host}" "${port}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

trino::start() {
  trino::ensure_dirs
  if [[ ! -x "${TRINO_HOME}/bin/launcher" ]]; then
    echo "[!] Trino launcher not found at ${TRINO_HOME}/bin/launcher; rebuild image." >&2
    return 1
  fi

  if trino::pid_alive && trino::port_open localhost "${TRINO_PORT}"; then
    echo "[*] Trino already running (PID $(cat "${TRINO_PID_FILE}"))."
    return 0
  fi

  pkill -f "io.trino.server.TrinoServer" >/dev/null 2>&1 || true
  echo "[*] Starting Trino on $(common::ui_url "${TRINO_PORT}" "/")..."
  env JAVA_HOME="${TRINO_JAVA_HOME}" PATH="${TRINO_JAVA_HOME}/bin:${PATH}" nohup "${TRINO_HOME}/bin/launcher" run --etc-dir "${TRINO_ETC_DIR}" --launcher-log-file "${TRINO_LOG_FILE}" \
    > "${TRINO_LOG_FILE}" 2>&1 &
  echo $! > "${TRINO_PID_FILE}"
  if ! trino::wait_for_port localhost "${TRINO_PORT}"; then
    echo "[!] Trino failed to open port ${TRINO_PORT}; see ${TRINO_LOG_FILE}" >&2
    return 1
  fi
  echo "[+] Trino started (PID $(cat "${TRINO_PID_FILE}"))."
}

trino::stop() {
  if [[ -x "${TRINO_HOME}/bin/launcher" ]]; then
    env JAVA_HOME="${TRINO_JAVA_HOME}" PATH="${TRINO_JAVA_HOME}/bin:${PATH}" "${TRINO_HOME}/bin/launcher" stop >/dev/null 2>&1 || true
  fi
  if trino::pid_alive; then
    kill "$(cat "${TRINO_PID_FILE}")" 2>/dev/null || true
  fi
  pkill -f "io.trino.server.TrinoServer" >/dev/null 2>&1 || true
  rm -f "${TRINO_PID_FILE}"
  echo "[+] Trino stopped."
}

trino::status() {
  if trino::pid_alive && trino::port_open localhost "${TRINO_PORT}"; then
    echo "[+] Trino: $(common::ui_url "${TRINO_PORT}" "/")"
  else
    echo "[-] Trino: not running"
  fi
}

trino::cli_exec() {
  local sql="${1:-}"
  if [[ -z "${sql}" ]]; then
    echo "[!] Missing SQL input for trino::cli_exec" >&2
    return 1
  fi
  if [[ -x "${TRINO_HOME}/bin/trino" ]]; then
    "${TRINO_HOME}/bin/trino" --server "localhost:${TRINO_PORT}" --user "${TRINO_USER}" --execute "${sql}"
    return 0
  fi

  TRINO_SQL="${sql}" TRINO_PORT="${TRINO_PORT}" TRINO_USER="${TRINO_USER}" python3 - <<'PY'
import json
import os
import sys
import urllib.request

sql = os.environ["TRINO_SQL"]
port = os.environ["TRINO_PORT"]
user = os.environ["TRINO_USER"]
url = f"http://localhost:{port}/v1/statement"

req = urllib.request.Request(url, data=sql.encode("utf-8"), method="POST")
req.add_header("X-Trino-User", user)
req.add_header("Content-Type", "text/plain; charset=utf-8")
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
except Exception as exc:
    print(f"[!] Trino HTTP query failed: {exc}", file=sys.stderr)
    sys.exit(1)

if payload.get("error"):
    message = payload["error"].get("message", "Unknown Trino error")
    print(f"[!] Trino query error: {message}", file=sys.stderr)
    sys.exit(1)
PY
}

trino::lakehouse_tests() {
  local catalog
  if ! trino::port_open localhost "${TRINO_PORT}"; then
    echo "[!] Trino is not reachable on port ${TRINO_PORT}. Start Trino first." >&2
    return 1
  fi

  echo "[*] Running lakehouse smoke tests via Trino..."
  trino::cli_exec "SHOW CATALOGS" >/dev/null

  for catalog in iceberg delta hudi; do
    echo "[*] Test (${catalog}): catalog availability + schema listing"
    trino::cli_exec "SHOW SCHEMAS FROM ${catalog}" >/dev/null
    trino::cli_exec "SELECT '${catalog}' AS catalog_name, count(*) AS schema_count FROM ${catalog}.information_schema.schemata;"
    echo "[+] ${catalog} test passed"
  done

  echo "[+] Lakehouse smoke tests passed (iceberg, delta, hudi)."
}
