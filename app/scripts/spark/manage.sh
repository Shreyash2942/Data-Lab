#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

: "${SPARK_MASTER_HOST:=localhost}"
: "${SPARK_MASTER_PORT:=7077}"
: "${SPARK_MASTER_WEBUI_PORT:=9090}"
: "${SPARK_WORKER_CORES:=2}"
: "${SPARK_WORKER_MEMORY:=2g}"
: "${SPARK_WORKER_PORT:=7081}"
: "${SPARK_WORKER_WEBUI_PORT:=9091}"

SPARK_MASTER_HOST="$(strip_cr "${SPARK_MASTER_HOST}")"
SPARK_MASTER_PORT="$(strip_cr "${SPARK_MASTER_PORT}")"
SPARK_MASTER_WEBUI_PORT="$(strip_cr "${SPARK_MASTER_WEBUI_PORT}")"
SPARK_WORKER_CORES="$(strip_cr "${SPARK_WORKER_CORES}")"
SPARK_WORKER_MEMORY="$(strip_cr "${SPARK_WORKER_MEMORY}")"
SPARK_WORKER_PORT="$(strip_cr "${SPARK_WORKER_PORT}")"
SPARK_WORKER_WEBUI_PORT="$(strip_cr "${SPARK_WORKER_WEBUI_PORT}")"

export SPARK_MASTER_HOST SPARK_MASTER_PORT SPARK_MASTER_WEBUI_PORT
export SPARK_WORKER_CORES SPARK_WORKER_MEMORY SPARK_WORKER_PORT SPARK_WORKER_WEBUI_PORT

spark::prepare_conf() {
  local conf_src="${SPARK_HOME}/conf"
  local conf_dst="${RUNTIME_ROOT}/spark/conf"
  mkdir -p "${conf_dst}"

  if [ -d "${conf_src}" ]; then
    while IFS= read -r -d '' path; do
      local base
      base="$(basename "${path}")"
      tr -d '\r' < "${path}" > "${conf_dst}/${base}"
      chmod --reference "${path}" "${conf_dst}/${base}" 2>/dev/null || true
    done < <(find "${conf_src}" -maxdepth 1 -type f -print0 2>/dev/null)
  fi

  export SPARK_CONF_DIR="${conf_dst}"
}

spark::ensure_dirs() {
  mkdir -p "${SPARK_PID_DIR}" "${SPARK_LOG_DIR}" "${SPARK_EVENTS_DIR}" "${SPARK_WAREHOUSE_DIR}"
}

spark::master_url() {
  printf 'spark://%s:%s\n' "${SPARK_MASTER_HOST}" "${SPARK_MASTER_PORT}"
}

spark::start_master() {
  local args=(
    --host "${SPARK_MASTER_HOST}"
    --port "${SPARK_MASTER_PORT}"
    --webui-port "${SPARK_MASTER_WEBUI_PORT}"
  )
  bash "${SPARK_HOME}/sbin/start-master.sh" "${args[@]}"
}

spark::start_worker() {
  local url
  url="$(spark::master_url)"
  local args=(
    --cores "${SPARK_WORKER_CORES}"
    --memory "${SPARK_WORKER_MEMORY}"
    --port "${SPARK_WORKER_PORT}"
    --webui-port "${SPARK_WORKER_WEBUI_PORT}"
  )
  bash "${SPARK_HOME}/sbin/start-worker.sh" "${args[@]}" "${url}"
}

spark::start_history_server() {
  bash "${SPARK_HOME}/sbin/start-history-server.sh"
}

spark::start() {
  spark::ensure_dirs
  spark::prepare_conf
  echo "[*] Starting Spark master, worker, and history server..."
  spark::start_master
  spark::start_worker
  spark::start_history_server
  echo "Spark master UI: http://localhost:${SPARK_MASTER_WEBUI_PORT}  |  History UI: http://localhost:18080"
}

spark::stop() {
  spark::prepare_conf
  echo "[*] Stopping Spark master, worker, and history server..."
  bash "${SPARK_HOME}/sbin/stop-history-server.sh" || true
  bash "${SPARK_HOME}/sbin/stop-worker.sh" || true
  bash "${SPARK_HOME}/sbin/stop-master.sh" || true
}
