#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

JUPYTER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${JUPYTER_SCRIPT_DIR}/../common.sh"

JUPYTER_BASE="${RUNTIME_ROOT}/jupyter"
JUPYTER_CONFIG_DIR="${JUPYTER_BASE}/config"
JUPYTER_DATA_DIR="${JUPYTER_BASE}/data"
JUPYTER_RUNTIME_DIR="${JUPYTER_BASE}/runtime"
JUPYTER_LOG_DIR="${JUPYTER_BASE}/logs"
JUPYTER_PID_DIR="${JUPYTER_BASE}/pids"
JUPYTER_NOTEBOOK_DIR="${JUPYTER_BASE}/notebooks"
JUPYTER_PID_FILE="${JUPYTER_PID_DIR}/jupyter.pid"
JUPYTER_LOG_FILE="${JUPYTER_LOG_DIR}/jupyter.log"
JUPYTER_TEMPLATE_NOTEBOOK="${JUPYTER_SCRIPT_DIR}/phase3_quickstart.ipynb"
JUPYTER_STARTER_NOTEBOOK="${JUPYTER_NOTEBOOK_DIR}/DataLab_Phase3_Quickstart.ipynb"

: "${JUPYTER_PORT:=8888}"
: "${JUPYTER_HOST:=0.0.0.0}"
: "${JUPYTER_TOKEN:=datalab}"
: "${JUPYTER_VENV_DIR:=/opt/jupyterlab-venv}"

JUPYTER_PORT="$(strip_cr "${JUPYTER_PORT}")"
JUPYTER_HOST="$(strip_cr "${JUPYTER_HOST}")"
JUPYTER_TOKEN="$(strip_cr "${JUPYTER_TOKEN}")"
JUPYTER_VENV_DIR="$(strip_cr "${JUPYTER_VENV_DIR}")"

jupyter::ensure_dirs() {
  mkdir -p \
    "${JUPYTER_CONFIG_DIR}" \
    "${JUPYTER_DATA_DIR}" \
    "${JUPYTER_RUNTIME_DIR}" \
    "${JUPYTER_LOG_DIR}" \
    "${JUPYTER_PID_DIR}" \
    "${JUPYTER_NOTEBOOK_DIR}"
}

jupyter::ensure_starter_notebook() {
  if [[ -f "${JUPYTER_TEMPLATE_NOTEBOOK}" && ! -f "${JUPYTER_STARTER_NOTEBOOK}" ]]; then
    cp "${JUPYTER_TEMPLATE_NOTEBOOK}" "${JUPYTER_STARTER_NOTEBOOK}"
  fi
}

jupyter::bin() {
  if [[ -x "${JUPYTER_VENV_DIR}/bin/jupyter-lab" ]]; then
    printf '%s' "${JUPYTER_VENV_DIR}/bin/jupyter-lab"
    return 0
  fi
  command -v jupyter-lab 2>/dev/null || true
}

jupyter::pid_alive() {
  [[ -f "${JUPYTER_PID_FILE}" ]] && kill -0 "$(cat "${JUPYTER_PID_FILE}")" 2>/dev/null
}

jupyter::cleanup_stale_pid() {
  if [[ -f "${JUPYTER_PID_FILE}" ]] && ! jupyter::pid_alive; then
    rm -f "${JUPYTER_PID_FILE}"
  fi
}

jupyter::port_open() {
  local host="$1" port="$2"
  JUPYTER_WAIT_HOST="${host}" JUPYTER_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["JUPYTER_WAIT_HOST"]
port = int(os.environ["JUPYTER_WAIT_PORT"])
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

jupyter::health_ready() {
  curl -fsS "http://127.0.0.1:${JUPYTER_PORT}/lab?token=${JUPYTER_TOKEN}" >/dev/null 2>&1
}

jupyter::wait_ready() {
  local deadline=$((SECONDS + 90))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if jupyter::health_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

jupyter::kill_pid_on_port() {
  local port="$1"
  local pids=""
  if command -v lsof >/dev/null 2>&1; then
    pids="$(lsof -t -iTCP:${port} -sTCP:LISTEN 2>/dev/null | tr '\n' ' ' || true)"
  elif command -v fuser >/dev/null 2>&1; then
    pids="$(fuser -n tcp "${port}" 2>/dev/null | tr ' ' '\n' | tr '\n' ' ' || true)"
  fi
  if [[ -n "${pids// }" ]]; then
    echo "[!] JupyterLab port ${port} is occupied by PID(s): ${pids}. Killing stale listener(s)..."
    # shellcheck disable=SC2086
    kill ${pids} 2>/dev/null || true
    sleep 1
  fi
}

jupyter::start() {
  local jupyter_bin=""

  jupyter::ensure_dirs
  jupyter::ensure_starter_notebook
  jupyter::cleanup_stale_pid
  jupyter_bin="$(jupyter::bin)"

  if [[ -z "${jupyter_bin}" ]]; then
    echo "[!] JupyterLab is not installed; cannot start Jupyter service." >&2
    return 1
  fi

  if jupyter::pid_alive && jupyter::port_open localhost "${JUPYTER_PORT}" && jupyter::health_ready; then
    echo "[*] JupyterLab already running (PID $(cat "${JUPYTER_PID_FILE}"))."
    return 0
  fi

  if jupyter::port_open localhost "${JUPYTER_PORT}"; then
    if jupyter::health_ready; then
      echo "[*] JupyterLab already reachable on ${JUPYTER_PORT}."
      return 0
    fi
    jupyter::kill_pid_on_port "${JUPYTER_PORT}"
    if jupyter::port_open localhost "${JUPYTER_PORT}"; then
      echo "[!] JupyterLab port ${JUPYTER_PORT} is in use by an unhealthy listener and could not be cleared." >&2
      return 1
    fi
  fi

  echo "[*] Starting JupyterLab on $(common::ui_url "${JUPYTER_PORT}" "/lab?token=${JUPYTER_TOKEN}")..."
  env \
    JUPYTER_CONFIG_DIR="${JUPYTER_CONFIG_DIR}" \
    JUPYTER_DATA_DIR="${JUPYTER_DATA_DIR}" \
    JUPYTER_RUNTIME_DIR="${JUPYTER_RUNTIME_DIR}" \
    nohup "${jupyter_bin}" \
      --ServerApp.ip="${JUPYTER_HOST}" \
      --ServerApp.port="${JUPYTER_PORT}" \
      --ServerApp.root_dir="${WORKSPACE}" \
      --ServerApp.open_browser=False \
      --ServerApp.token="${JUPYTER_TOKEN}" \
      --ServerApp.password='' \
      > "${JUPYTER_LOG_FILE}" 2>&1 &
  echo $! > "${JUPYTER_PID_FILE}"

  if ! jupyter::wait_ready; then
    echo "[!] JupyterLab failed to open port ${JUPYTER_PORT}; recent log lines:" >&2
    tail -n 80 "${JUPYTER_LOG_FILE}" >&2 || true
    return 1
  fi

  echo "JupyterLab: $(common::ui_url "${JUPYTER_PORT}" "/lab?token=${JUPYTER_TOKEN}")"
  echo "Starter notebook: ${JUPYTER_STARTER_NOTEBOOK}"
}

jupyter::stop() {
  jupyter::cleanup_stale_pid
  if jupyter::pid_alive; then
    echo "[*] Stopping JupyterLab..."
    kill "$(cat "${JUPYTER_PID_FILE}")" 2>/dev/null || true
    rm -f "${JUPYTER_PID_FILE}"
    sleep 1
  else
    rm -f "${JUPYTER_PID_FILE}"
  fi
  pkill -f "${JUPYTER_VENV_DIR}/bin/jupyter-lab" >/dev/null 2>&1 || true
}

jupyter::status() {
  local ok=0
  if jupyter::port_open localhost "${JUPYTER_PORT}"; then
    echo "[+] JupyterLab port ${JUPYTER_PORT} is listening."
  else
    echo "[-] JupyterLab port ${JUPYTER_PORT} is not listening."
    ok=1
  fi

  if jupyter::health_ready; then
    echo "[+] JupyterLab is reachable at $(common::ui_url "${JUPYTER_PORT}" "/lab?token=${JUPYTER_TOKEN}")"
  else
    echo "[-] JupyterLab is not reachable."
    ok=1
  fi

  return "${ok}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-start}"
  case "${cmd}" in
    start)
      jupyter::start
      ;;
    stop)
      jupyter::stop
      ;;
    restart)
      jupyter::stop || true
      sleep 1
      jupyter::start
      ;;
    status)
      jupyter::status
      ;;
    *)
      echo "Usage: $0 {start|stop|restart|status}" >&2
      exit 2
      ;;
  esac
fi
