#!/usr/bin/env bash
# Shared environment/bootstrap helpers for Data Lab service scripts.

if [[ -n "${DATALAB_COMMON_LOADED:-}" ]] && declare -F strip_cr >/dev/null 2>&1; then
  return 0
fi
DATALAB_COMMON_LOADED=1

strip_cr() {
  local value="${1:-}"
  value="${value//$'\r'/}"
  printf '%s' "${value}"
}

DATALAB_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATALAB_REPO_ROOT="$(cd "${DATALAB_SCRIPTS_DIR}/../.." && pwd)"

common::init_workdir() {
  HOME_DIR="$(strip_cr "${HOME:-/home/datalab}")"
  WORKSPACE="$(strip_cr "${WORKSPACE:-${HOME_DIR}}")"
  RUNTIME_ROOT="$(strip_cr "${RUNTIME_ROOT:-${WORKSPACE}/runtime}")"

  mkdir -p "${RUNTIME_ROOT}"
  export HOME_DIR WORKSPACE RUNTIME_ROOT

  HDFS_BASE="${RUNTIME_ROOT}/hadoop/dfs"
  HDFS_NAME_DIR="${HDFS_BASE}/name"
  HDFS_DATA_DIR="${HDFS_BASE}/data"
  SPARK_PID_DIR="${RUNTIME_ROOT}/spark/pids"
  SPARK_LOG_DIR="${RUNTIME_ROOT}/spark/logs"
  SPARK_EVENTS_DIR="${RUNTIME_ROOT}/spark/events"
  SPARK_WAREHOUSE_DIR="${RUNTIME_ROOT}/spark/warehouse"
  HIVE_METASTORE_DB="${RUNTIME_ROOT}/hive/metastore_db"
  HIVE_WAREHOUSE="${RUNTIME_ROOT}/hive/warehouse"
  HIVE_PID_DIR="${RUNTIME_ROOT}/hive/pids"
  HIVE_LOG_DIR="${RUNTIME_ROOT}/hive/logs"
  KAFKA_BASE="${RUNTIME_ROOT}/kafka"
  KAFKA_PID_DIR="${KAFKA_BASE}/pids"
  KAFKA_LOG_DIR="${KAFKA_BASE}/logs"
  KAFKA_DATA_DIR="${KAFKA_BASE}/data"
  KAFKA_ZK_DATA_DIR="${KAFKA_BASE}/zookeeper-data"
  HADOOP_LOG_DIR="${RUNTIME_ROOT}/hadoop/logs"
  YARN_LOG_DIR="${RUNTIME_ROOT}/hadoop/logs/yarn"
  MAPRED_LOG_DIR="${RUNTIME_ROOT}/hadoop/logs/mapred"
  AIRFLOW_PID_DIR="${RUNTIME_ROOT}/airflow/pids"

  mkdir -p \
    "${HIVE_LOG_DIR}" \
    "${HIVE_PID_DIR}" \
    "${KAFKA_DATA_DIR}" \
    "${KAFKA_LOG_DIR}" \
    "${KAFKA_PID_DIR}" \
    "${AIRFLOW_PID_DIR}"

  if [[ "$(id -u)" -eq 0 ]]; then
    local app_user="${LAB_APP_USER:-datalab}"
    chown -R "${app_user}:${app_user}" \
      "${RUNTIME_ROOT}" \
      "${HDFS_BASE}" \
      "${SPARK_PID_DIR}" "${SPARK_LOG_DIR}" "${SPARK_EVENTS_DIR}" "${SPARK_WAREHOUSE_DIR}" \
      "${HIVE_METASTORE_DB}" "${HIVE_WAREHOUSE}" "${HIVE_PID_DIR}" "${HIVE_LOG_DIR}" \
      "${KAFKA_BASE}" "${KAFKA_PID_DIR}" "${KAFKA_LOG_DIR}" "${KAFKA_DATA_DIR}" "${KAFKA_ZK_DATA_DIR}" \
      "${HADOOP_LOG_DIR}" "${YARN_LOG_DIR}" "${MAPRED_LOG_DIR}" \
      "${AIRFLOW_PID_DIR}" 2>/dev/null || true
  fi

  APP_BIN_DIR="${WORKSPACE}/app/bin"
  mkdir -p "${APP_BIN_DIR}"

  export APP_BIN_DIR HDFS_BASE HDFS_NAME_DIR HDFS_DATA_DIR \
    SPARK_PID_DIR SPARK_LOG_DIR SPARK_EVENTS_DIR SPARK_WAREHOUSE_DIR \
    HIVE_METASTORE_DB HIVE_WAREHOUSE HIVE_PID_DIR HIVE_LOG_DIR \
    KAFKA_BASE KAFKA_PID_DIR KAFKA_LOG_DIR KAFKA_DATA_DIR KAFKA_ZK_DATA_DIR \
    HADOOP_LOG_DIR YARN_LOG_DIR MAPRED_LOG_DIR AIRFLOW_PID_DIR
}

common::init_workdir

: "${DATALAB_RUNTIME_CONFIG_DIR:=${RUNTIME_ROOT}/config}"
: "${DATALAB_RUNTIME_OVERRIDE_FILE:=${DATALAB_RUNTIME_CONFIG_DIR}/datalab-overrides.env}"
: "${DATALAB_SPARK_CPU_LIMIT_PERCENT:=60}"
mkdir -p "${DATALAB_RUNTIME_CONFIG_DIR}"
export DATALAB_RUNTIME_CONFIG_DIR DATALAB_RUNTIME_OVERRIDE_FILE DATALAB_SPARK_CPU_LIMIT_PERCENT

common::load_runtime_overrides() {
  local override_file="${DATALAB_RUNTIME_OVERRIDE_FILE}"
  if [[ ! -f "${override_file}" ]]; then
    return 0
  fi

  set -a
  # shellcheck source=/dev/null
  source "${override_file}"
  set +a
}

common::load_runtime_overrides

common::detect_effective_cpu() {
  python3 - <<'PY'
import math
import os

def read_first(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""

host_cpu = max(1, os.cpu_count() or 1)
limit_cpu = None

cpu_max = read_first("/sys/fs/cgroup/cpu.max")
if cpu_max:
    parts = cpu_max.split()
    if len(parts) == 2 and parts[0] != "max":
        quota = int(parts[0])
        period = int(parts[1])
        if quota > 0 and period > 0:
            limit_cpu = max(1, math.floor(quota / period))

if limit_cpu is None:
    quota = read_first("/sys/fs/cgroup/cpu/cpu.cfs_quota_us")
    period = read_first("/sys/fs/cgroup/cpu/cpu.cfs_period_us")
    if quota and period and quota != "-1":
        quota_i = int(quota)
        period_i = int(period)
        if quota_i > 0 and period_i > 0:
            limit_cpu = max(1, math.floor(quota_i / period_i))

effective_cpu = min(host_cpu, limit_cpu) if limit_cpu is not None else host_cpu
print(effective_cpu)
PY
}

common::spark_worker_core_cap() {
  local effective_cpu
  effective_cpu="$(common::detect_effective_cpu)"
  EFFECTIVE_CPU_RAW="$(strip_cr "${effective_cpu}")"
  if [[ ! "${EFFECTIVE_CPU_RAW}" =~ ^[0-9]+$ ]] || [[ "${EFFECTIVE_CPU_RAW}" -le 0 ]]; then
    EFFECTIVE_CPU_RAW=1
  fi
  local cap=$(( (EFFECTIVE_CPU_RAW * DATALAB_SPARK_CPU_LIMIT_PERCENT) / 100 ))
  if [[ "${cap}" -lt 1 ]]; then
    cap=1
  fi
  printf '%s' "${cap}"
}

common::enforce_runtime_limits() {
  local spark_core_cap
  spark_core_cap="$(common::spark_worker_core_cap)"

  if [[ -n "${SPARK_WORKER_CORES:-}" ]] && [[ "${SPARK_WORKER_CORES}" =~ ^[0-9]+$ ]] && [[ "${SPARK_WORKER_CORES}" -gt "${spark_core_cap}" ]]; then
    echo "[!] SPARK_WORKER_CORES=${SPARK_WORKER_CORES} exceeds ${DATALAB_SPARK_CPU_LIMIT_PERCENT}% CPU limit. Clamping to ${spark_core_cap}." >&2
    SPARK_WORKER_CORES="${spark_core_cap}"
    export SPARK_WORKER_CORES
  fi

  if [[ -n "${DATALAB_SPARK_APP_MAX_CORES:-}" ]] && [[ "${DATALAB_SPARK_APP_MAX_CORES}" =~ ^[0-9]+$ ]] && \
     [[ -n "${SPARK_WORKER_CORES:-}" ]] && [[ "${SPARK_WORKER_CORES}" =~ ^[0-9]+$ ]] && \
     [[ "${DATALAB_SPARK_APP_MAX_CORES}" -gt "${SPARK_WORKER_CORES}" ]]; then
    echo "[!] DATALAB_SPARK_APP_MAX_CORES=${DATALAB_SPARK_APP_MAX_CORES} exceeds SPARK_WORKER_CORES=${SPARK_WORKER_CORES}. Clamping app max cores to ${SPARK_WORKER_CORES}." >&2
    DATALAB_SPARK_APP_MAX_CORES="${SPARK_WORKER_CORES}"
    export DATALAB_SPARK_APP_MAX_CORES
  fi
}

common::enforce_runtime_limits

: "${SPARK_HOME:=/opt/spark}"
: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_COMMON_LIB_NATIVE_DIR:=${HADOOP_HOME}/lib/native}"
: "${HADOOP_MAPRED_HOME:=${HADOOP_HOME}}"
: "${HIVE_HOME:=/opt/hive}"
: "${KAFKA_HOME:=/opt/kafka}"
: "${HIVE_SERVER2_THRIFT_PORT:=10000}"
: "${HIVE_SERVER2_THRIFT_HOST:=0.0.0.0}"
: "${HIVE_SERVER2_HTTP_PORT:=10001}"
: "${HIVE_SERVER2_HTTP_PATH:=cliservice}"

SPARK_HOME="$(strip_cr "${SPARK_HOME}")"
HADOOP_HOME="$(strip_cr "${HADOOP_HOME}")"
HADOOP_COMMON_LIB_NATIVE_DIR="$(strip_cr "${HADOOP_COMMON_LIB_NATIVE_DIR}")"
HADOOP_MAPRED_HOME="$(strip_cr "${HADOOP_MAPRED_HOME}")"
HIVE_HOME="$(strip_cr "${HIVE_HOME}")"
KAFKA_HOME="$(strip_cr "${KAFKA_HOME}")"
HIVE_SERVER2_THRIFT_PORT="$(strip_cr "${HIVE_SERVER2_THRIFT_PORT}")"
HIVE_SERVER2_THRIFT_HOST="$(strip_cr "${HIVE_SERVER2_THRIFT_HOST}")"
HIVE_SERVER2_HTTP_PORT="$(strip_cr "${HIVE_SERVER2_HTTP_PORT}")"
HIVE_SERVER2_HTTP_PATH="$(strip_cr "${HIVE_SERVER2_HTTP_PATH}")"

export SPARK_HOME HADOOP_HOME HADOOP_COMMON_LIB_NATIVE_DIR HADOOP_MAPRED_HOME HIVE_HOME KAFKA_HOME \
  HIVE_SERVER2_THRIFT_PORT HIVE_SERVER2_THRIFT_HOST \
  HIVE_SERVER2_HTTP_PORT HIVE_SERVER2_HTTP_PATH

HDFS_BIN="${HADOOP_HOME}/bin/hdfs"
YARN_BIN="${HADOOP_HOME}/bin/yarn"
MAPRED_BIN="${HADOOP_HOME}/bin/mapred"
HADOOP_BIN="${HADOOP_HOME}/bin/hadoop"
HIVE_BIN="${HIVE_HOME}/bin/hive"
SCHEMATOOL_BIN="${HIVE_HOME}/bin/schematool"

export HDFS_BIN YARN_BIN MAPRED_BIN HADOOP_BIN HIVE_BIN SCHEMATOOL_BIN

: "${JAVA_HOME:=/usr/lib/jvm/java-11-openjdk-amd64}"
JAVA_HOME="$(strip_cr "${JAVA_HOME}")"
export JAVA_HOME
export HADOOP_CONF_DIR="${HADOOP_HOME}/etc/hadoop"
# Avoid deprecated YARN_CONF_DIR warnings from newer Hadoop CLIs.
if [[ -n "${YARN_CONF_DIR:-}" ]]; then
  unset YARN_CONF_DIR
fi
case ":$PATH:" in
  *":${JAVA_HOME}/bin:"*) ;;
  *) export PATH="${PATH}:${JAVA_HOME}/bin" ;;
esac

case ":${LD_LIBRARY_PATH:-}:" in
  *":${HADOOP_COMMON_LIB_NATIVE_DIR}:"*) ;;
  *) export LD_LIBRARY_PATH="${HADOOP_COMMON_LIB_NATIVE_DIR}:${LD_LIBRARY_PATH:-}" ;;
esac

case ":$PATH:" in
  *":${APP_BIN_DIR}:"*) ;;
  *) export PATH="${APP_BIN_DIR}:$PATH" ;;
esac

common::ensure_cli_shortcuts() {
  local rc_file="${HOME}/.bashrc"
  local export_line='export PATH="'"${WORKSPACE}"'/app/bin:$PATH"'
  local hive_alias="alias hive='bash \"${WORKSPACE}/app/bin/hive\"'"
  local dbt_alias="alias dbt='bash \"${WORKSPACE}/app/bin/dbt\"'"
  local spark_submit_alias="alias spark-submit='bash \"${WORKSPACE}/app/bin/spark-submit\"'"
  local spark_sql_alias="alias spark-sql='bash \"${WORKSPACE}/app/bin/spark-sql\"'"
  local profile_file="${HOME}/.profile"

  if [ ! -e "${rc_file}" ]; then
    printf '# Data Lab CLI shortcuts\n%s\n%s\n%s\n%s\n%s\n' "${export_line}" "${hive_alias}" "${dbt_alias}" "${spark_submit_alias}" "${spark_sql_alias}" > "${rc_file}" 2>/dev/null || true
    return
  fi

  if [ -w "${rc_file}" ] && ! grep -Fq 'app/bin' "${rc_file}" 2>/dev/null; then
    printf '\n# Data Lab CLI shortcuts\n%s\n' "${export_line}" >> "${rc_file}" 2>/dev/null || true
  fi

  if [ -w "${rc_file}" ] && ! grep -Fq "${hive_alias}" "${rc_file}" 2>/dev/null; then
    printf '%s\n' "${hive_alias}" >> "${rc_file}" 2>/dev/null || true
  fi
  if [ -w "${rc_file}" ] && ! grep -Fq "${dbt_alias}" "${rc_file}" 2>/dev/null; then
    printf '%s\n' "${dbt_alias}" >> "${rc_file}" 2>/dev/null || true
  fi
  if [ -w "${rc_file}" ] && ! grep -Fq "${spark_submit_alias}" "${rc_file}" 2>/dev/null; then
    printf '%s\n' "${spark_submit_alias}" >> "${rc_file}" 2>/dev/null || true
  fi
  if [ -w "${rc_file}" ] && ! grep -Fq "${spark_sql_alias}" "${rc_file}" 2>/dev/null; then
    printf '%s\n' "${spark_sql_alias}" >> "${rc_file}" 2>/dev/null || true
  fi

  # Ensure login shells also pick up the alias/PATH
  if [ ! -e "${profile_file}" ]; then
    printf '%s\n%s\n%s\n%s\n%s\n' "${export_line}" "${hive_alias}" "${dbt_alias}" "${spark_submit_alias}" "${spark_sql_alias}" > "${profile_file}" 2>/dev/null || true
  else
    if [ -w "${profile_file}" ] && ! grep -Fq 'app/bin' "${profile_file}" 2>/dev/null; then
      printf '%s\n' "${export_line}" >> "${profile_file}" 2>/dev/null || true
    fi
    if [ -w "${profile_file}" ] && ! grep -Fq "${hive_alias}" "${profile_file}" 2>/dev/null; then
      printf '%s\n' "${hive_alias}" >> "${profile_file}" 2>/dev/null || true
    fi
    if [ -w "${profile_file}" ] && ! grep -Fq "${dbt_alias}" "${profile_file}" 2>/dev/null; then
      printf '%s\n' "${dbt_alias}" >> "${profile_file}" 2>/dev/null || true
    fi
    if [ -w "${profile_file}" ] && ! grep -Fq "${spark_submit_alias}" "${profile_file}" 2>/dev/null; then
      printf '%s\n' "${spark_submit_alias}" >> "${profile_file}" 2>/dev/null || true
    fi
    if [ -w "${profile_file}" ] && ! grep -Fq "${spark_sql_alias}" "${profile_file}" 2>/dev/null; then
      printf '%s\n' "${spark_sql_alias}" >> "${profile_file}" 2>/dev/null || true
    fi
  fi
}

common::ensure_cli_shortcuts

export SPARK_PID_DIR SPARK_LOG_DIR SPARK_EVENTS_DIR
export SPARK_HISTORY_OPTS="-Dspark.history.fs.logDirectory=file://${SPARK_EVENTS_DIR}"
export HADOOP_LOG_DIR MAPRED_LOG_DIR
export HIVE_PID_DIR
export _HIVE_PID_DIR="${HIVE_PID_DIR}"
export HIVE_SERVER2_PID_DIR="${HIVE_PID_DIR}"
export HIVE_METASTORE_PID_DIR="${HIVE_PID_DIR}"
export HIVESERVER2_PID_DIR="${HIVE_PID_DIR}"
export METASTORE_PID_DIR="${HIVE_PID_DIR}"
export HIVE_LOG_DIR
export HIVE_CONF_DIR="${HIVE_HOME}/conf"
: "${DATALAB_UI_HOST:=localhost}"
: "${DATALAB_HOST_PORT_MAP:=}"
: "${UI_MAP_FILE:=/home/datalab/runtime/ui-port-map.env}"
export DATALAB_UI_HOST DATALAB_HOST_PORT_MAP UI_MAP_FILE

common::load_ui_map() {
  if [[ -n "${DATALAB_HOST_PORT_MAP}" ]]; then
    return 0
  fi
  if [[ ! -f "${UI_MAP_FILE}" ]]; then
    return 0
  fi

  while IFS='=' read -r key value; do
    key="$(strip_cr "${key}")"
    value="$(strip_cr "${value}")"
    case "${key}" in
      DATALAB_UI_HOST) [[ -n "${value}" ]] && DATALAB_UI_HOST="${value}" ;;
      DATALAB_HOST_PORT_MAP) [[ -n "${value}" ]] && DATALAB_HOST_PORT_MAP="${value}" ;;
    esac
  done < "${UI_MAP_FILE}"
}

common::mapped_host_port() {
  local container_port="${1:-}"
  local entry cport hport
  common::load_ui_map
  [[ -n "${container_port}" ]] || return 1

  if [[ -n "${DATALAB_HOST_PORT_MAP}" ]]; then
    IFS=',' read -ra _entries <<< "${DATALAB_HOST_PORT_MAP}"
    for entry in "${_entries[@]}"; do
      entry="$(strip_cr "${entry}")"
      cport="${entry%%=*}"
      hport="${entry#*=}"
      if [[ "${cport}" == "${container_port}" ]] && [[ "${hport}" =~ ^[0-9]+$ ]]; then
        printf '%s' "${hport}"
        return 0
      fi
    done
  fi

  printf '%s' "${container_port}"
}

common::ui_url() {
  local container_port="${1:-}"
  local path="${2:-/}"
  local host_port
  host_port="$(common::mapped_host_port "${container_port}")"
  printf 'http://%s:%s%s' "${DATALAB_UI_HOST}" "${host_port}" "${path}"
}

common::resolve_lakehouse_root() {
  local candidate
  local -a candidates=(
    "${LAKEHOUSE_STACK_ROOT:-}"
    "${LAKEHOUSE_ROOT:-}"
    "${WORKSPACE}/lakehouse"
    "/home/datalab/lakehouse"
    "${WORKSPACE}/stacks/lakehouse"
    "${DATALAB_REPO_ROOT}/stacks/lakehouse"
  )

  for candidate in "${candidates[@]}"; do
    candidate="$(strip_cr "${candidate}")"
    [[ -z "${candidate}" ]] && continue
    if [[ -d "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

common::lakehouse_root_hint() {
  local -a candidates=(
    "${LAKEHOUSE_STACK_ROOT:-<unset>}"
    "${LAKEHOUSE_ROOT:-<unset>}"
    "${WORKSPACE}/lakehouse"
    "/home/datalab/lakehouse"
    "${WORKSPACE}/stacks/lakehouse"
    "${DATALAB_REPO_ROOT}/stacks/lakehouse"
  )
  printf '%s' "${candidates[*]}"
}

common::require_lakehouse_root() {
  local root
  root="$(common::resolve_lakehouse_root || true)"
  if [[ -z "${root}" ]]; then
    echo "[!] Lakehouse asset root not found. Checked: $(common::lakehouse_root_hint)" >&2
    return 1
  fi
  printf '%s' "${root}"
}

common::assert_inside_container() {
  if [ -f "/.dockerenv" ] || [ -n "${INSIDE_DATALAB:-}" ]; then
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "Please run inside the data-lab container or install Docker CLI." >&2
    exit 1
  fi

  (
    cd "${DATALAB_REPO_ROOT}"
    docker compose exec -e INSIDE_DATALAB=1 data-lab "$0" "$@"
  )
  exit $?
}
