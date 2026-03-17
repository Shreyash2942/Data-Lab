#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

GX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${GX_SCRIPT_DIR}/../common.sh"

GX_BASE="${RUNTIME_ROOT}/great_expectations"
GX_PROJECT_ROOT="${GX_BASE}/project"
GX_DATA_DIR="${GX_BASE}/demo_data"
GX_LOG_DIR="${GX_BASE}/logs"
GX_PID_DIR="${GX_BASE}/pids"
GX_PID_FILE="${GX_PID_DIR}/gx-docs.pid"
GX_LOG_FILE="${GX_LOG_DIR}/gx-docs.log"
GX_RESULT_FILE="${GX_BASE}/last_validation.json"
GX_DEMO_SCRIPT="${GX_SCRIPT_DIR}/validate_demo.py"

: "${GX_DOCS_PORT:=8891}"
: "${GX_DOCS_HOST:=0.0.0.0}"
: "${GX_VENV_DIR:=/opt/gx-venv}"

GX_DOCS_PORT="$(strip_cr "${GX_DOCS_PORT}")"
GX_DOCS_HOST="$(strip_cr "${GX_DOCS_HOST}")"
GX_VENV_DIR="$(strip_cr "${GX_VENV_DIR}")"

gx::ensure_dirs() {
  mkdir -p "${GX_PROJECT_ROOT}" "${GX_DATA_DIR}" "${GX_LOG_DIR}" "${GX_PID_DIR}"
}

gx::python_bin() {
  if [[ -x "${GX_VENV_DIR}/bin/python" ]]; then
    printf '%s' "${GX_VENV_DIR}/bin/python"
    return 0
  fi
  command -v python3 2>/dev/null || true
}

gx::pid_alive() {
  [[ -f "${GX_PID_FILE}" ]] && kill -0 "$(cat "${GX_PID_FILE}")" 2>/dev/null
}

gx::cleanup_stale_pid() {
  if [[ -f "${GX_PID_FILE}" ]] && ! gx::pid_alive; then
    rm -f "${GX_PID_FILE}"
  fi
}

gx::port_open() {
  local host="$1" port="$2"
  GX_WAIT_HOST="${host}" GX_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["GX_WAIT_HOST"]
port = int(os.environ["GX_WAIT_PORT"])
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

gx::health_ready() {
  curl -fsS "http://127.0.0.1:${GX_DOCS_PORT}/" >/dev/null 2>&1
}

gx::wait_ready() {
  local deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if gx::health_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

gx::kill_pid_on_port() {
  local port="$1"
  local pids=""
  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -t -iTCP:${port} -sTCP:LISTEN 2>/dev/null | tr '\n' ' ' || true)"
  elif command -v fuser >/dev/null 2>&1; then
    pids="$(fuser -n tcp "${port}" 2>/dev/null | tr ' ' '\n' | tr '\n' ' ' || true)"
  fi
  if [[ -n "${pids// }" ]]; then
    echo "[!] Great Expectations docs port ${port} is occupied by PID(s): ${pids}. Killing stale listener(s)..."
    # shellcheck disable=SC2086
    kill ${pids} 2>/dev/null || true
    sleep 1
  fi
}

gx::read_result_field() {
  local field="$1"
  local py_bin
  py_bin="$(gx::python_bin)"
  [[ -f "${GX_RESULT_FILE}" ]] || return 1
  "${py_bin}" - "${GX_RESULT_FILE}" "${field}" <<'PY'
import json
import sys
from pathlib import Path

result_path = Path(sys.argv[1])
field = sys.argv[2]
payload = json.loads(result_path.read_text(encoding="utf-8"))
value = payload.get(field, "")
if value is None:
    value = ""
print(value)
PY
}

gx::docs_root() {
  gx::read_result_field "docs_site_dir"
}

gx::run_demo_validation() {
  local py_bin
  py_bin="$(gx::python_bin)"

  gx::ensure_dirs
  if [[ -z "${py_bin}" ]]; then
    echo "[!] Great Expectations Python runtime not found." >&2
    return 1
  fi
  if [[ ! -f "${GX_DEMO_SCRIPT}" ]]; then
    echo "[!] Great Expectations demo script not found: ${GX_DEMO_SCRIPT}" >&2
    return 1
  fi

  echo "[*] Running Great Expectations demo validation..."
  if ! env \
    GX_ANALYTICS_ENABLED=False \
    GX_PROJECT_ROOT="${GX_PROJECT_ROOT}" \
    GX_DATA_DIR="${GX_DATA_DIR}" \
    GX_RESULT_JSON="${GX_RESULT_FILE}" \
    "${py_bin}" "${GX_DEMO_SCRIPT}" > "${GX_LOG_FILE}" 2>&1; then
    if [[ -f "${GX_RESULT_FILE}" ]] && [[ "$(gx::read_result_field success || true)" == "True" ]]; then
      :
    else
      echo "[!] Great Expectations demo validation command failed. Recent log lines:" >&2
      tail -n 80 "${GX_LOG_FILE}" >&2 || true
      return 1
    fi
  fi

  if [[ ! -f "${GX_RESULT_FILE}" ]]; then
    echo "[!] Great Expectations demo did not produce a result file. Check ${GX_LOG_FILE}." >&2
    return 1
  fi

  if [[ "$(gx::read_result_field success || true)" != "True" ]]; then
    echo "[!] Great Expectations validation failed. Recent log lines:" >&2
    tail -n 80 "${GX_LOG_FILE}" >&2 || true
    return 1
  fi

  echo "Great Expectations Data Docs: $(common::ui_url "${GX_DOCS_PORT}" "/")"
}

gx::start() {
  local docs_root=""

  gx::cleanup_stale_pid
  gx::run_demo_validation
  docs_root="$(gx::docs_root)"

  if [[ -z "${docs_root}" || ! -d "${docs_root}" ]]; then
    echo "[!] Great Expectations Data Docs directory is missing. Check ${GX_RESULT_FILE} and ${GX_LOG_FILE}." >&2
    return 1
  fi

  if gx::pid_alive && gx::port_open localhost "${GX_DOCS_PORT}" && gx::health_ready; then
    echo "[*] Great Expectations Data Docs already running (PID $(cat "${GX_PID_FILE}"))."
    return 0
  fi

  if gx::port_open localhost "${GX_DOCS_PORT}"; then
    if gx::health_ready; then
      echo "[*] Great Expectations Data Docs already reachable on ${GX_DOCS_PORT}."
      return 0
    fi
    gx::kill_pid_on_port "${GX_DOCS_PORT}"
    if gx::port_open localhost "${GX_DOCS_PORT}"; then
      echo "[!] Great Expectations docs port ${GX_DOCS_PORT} is in use by an unhealthy listener and could not be cleared." >&2
      return 1
    fi
  fi

  echo "[*] Starting Great Expectations Data Docs on $(common::ui_url "${GX_DOCS_PORT}" "/")..."
  (
    cd "${docs_root}"
    nohup python3 -m http.server "${GX_DOCS_PORT}" --bind "${GX_DOCS_HOST}" > "${GX_LOG_FILE}" 2>&1 &
    echo $! > "${GX_PID_FILE}"
  )

  if ! gx::wait_ready; then
    echo "[!] Great Expectations Data Docs failed to open port ${GX_DOCS_PORT}; recent log lines:" >&2
    tail -n 80 "${GX_LOG_FILE}" >&2 || true
    return 1
  fi

  echo "Great Expectations Data Docs: $(common::ui_url "${GX_DOCS_PORT}" "/")"
}

gx::stop() {
  gx::cleanup_stale_pid
  if gx::pid_alive; then
    echo "[*] Stopping Great Expectations Data Docs..."
    kill "$(cat "${GX_PID_FILE}")" 2>/dev/null || true
    rm -f "${GX_PID_FILE}"
    sleep 1
  else
    rm -f "${GX_PID_FILE}"
  fi
  pkill -f "http.server ${GX_DOCS_PORT}" >/dev/null 2>&1 || true
}

gx::status() {
  local ok=0

  if [[ -f "${GX_RESULT_FILE}" ]]; then
    echo "[+] Great Expectations result file present: ${GX_RESULT_FILE}"
  else
    echo "[-] Great Expectations result file is missing."
    ok=1
  fi

  if gx::port_open localhost "${GX_DOCS_PORT}"; then
    echo "[+] Great Expectations Data Docs port ${GX_DOCS_PORT} is listening."
  else
    echo "[-] Great Expectations Data Docs port ${GX_DOCS_PORT} is not listening."
    ok=1
  fi

  return "${ok}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-start}"
  case "${cmd}" in
    start)
      gx::start
      ;;
    stop)
      gx::stop
      ;;
    restart)
      gx::stop || true
      sleep 1
      gx::start
      ;;
    run-demo|validate)
      gx::run_demo_validation
      ;;
    status)
      gx::status
      ;;
    *)
      echo "Usage: $0 {start|stop|restart|run-demo|validate|status}" >&2
      exit 2
      ;;
  esac
fi
