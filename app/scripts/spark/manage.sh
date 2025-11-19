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
: "${SPARK_WORKER_DIR:=${RUNTIME_ROOT}/spark/work}"

SPARK_MASTER_HOST="$(strip_cr "${SPARK_MASTER_HOST}")"
SPARK_MASTER_PORT="$(strip_cr "${SPARK_MASTER_PORT}")"
SPARK_MASTER_WEBUI_PORT="$(strip_cr "${SPARK_MASTER_WEBUI_PORT}")"
SPARK_WORKER_CORES="$(strip_cr "${SPARK_WORKER_CORES}")"
SPARK_WORKER_MEMORY="$(strip_cr "${SPARK_WORKER_MEMORY}")"
SPARK_WORKER_PORT="$(strip_cr "${SPARK_WORKER_PORT}")"
SPARK_WORKER_WEBUI_PORT="$(strip_cr "${SPARK_WORKER_WEBUI_PORT}")"
SPARK_WORKER_DIR="$(strip_cr "${SPARK_WORKER_DIR}")"

export SPARK_MASTER_HOST SPARK_MASTER_PORT SPARK_MASTER_WEBUI_PORT
export SPARK_WORKER_CORES SPARK_WORKER_MEMORY SPARK_WORKER_PORT SPARK_WORKER_WEBUI_PORT SPARK_WORKER_DIR

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

  spark::ensure_log4j "${conf_src}" "${conf_dst}"
  local log4j_file="${conf_dst}/log4j2.properties"
  spark::tune_log4j "${log4j_file}"
  export SPARK_SUBMIT_OPTS="-Dlog4j.configurationFile=${log4j_file} ${SPARK_SUBMIT_OPTS:-}"

  export SPARK_CONF_DIR="${conf_dst}"
}

spark::ensure_log4j() {
  local conf_src="$1"
  local conf_dst="$2"
  local log4j_file="${conf_dst}/log4j2.properties"

  if [ -f "${log4j_file}" ]; then
    return
  fi

  local template_src="${conf_dst}/log4j2.properties.template"
  if [ ! -f "${template_src}" ] && [ -f "${conf_src}/log4j2.properties.template" ]; then
    template_src="${conf_src}/log4j2.properties.template"
  fi

  if [ -f "${template_src}" ]; then
    tr -d '\r' < "${template_src}" > "${log4j_file}"
  else
    printf 'rootLogger.level = INFO\n' > "${log4j_file}"
  fi
}

spark::tune_log4j() {
  local file="$1"
  if [ ! -f "${file}" ]; then
    return
  fi
  if grep -q "rootLogger.level" "${file}"; then
    perl -0pi -e 's/rootLogger\.level\s*=\s*\w+/rootLogger.level = WARN/' "${file}"
  else
    printf '\nrootLogger.level = WARN\n' >> "${file}"
  fi
  if ! grep -q "logger.spark.level" "${file}"; then
    printf 'logger.spark.name = org.apache.spark\nlogger.spark.level = WARN\n' >> "${file}"
  fi

  if ! grep -q "logger.hadoop.level" "${file}"; then
    cat >> "${file}" <<'EOF'
logger.hadoop.name = org.apache.hadoop.util.NativeCodeLoader
logger.hadoop.level = ERROR
EOF
  fi
}

spark::ensure_dirs() {
  mkdir -p "${SPARK_PID_DIR}" "${SPARK_LOG_DIR}" "${SPARK_EVENTS_DIR}" "${SPARK_WAREHOUSE_DIR}" "${SPARK_WORKER_DIR}"
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
