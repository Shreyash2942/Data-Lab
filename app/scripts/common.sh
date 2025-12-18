#!/usr/bin/env bash
# Shared environment/bootstrap helpers for Data Lab service scripts.

if [[ -n "${DATALAB_COMMON_LOADED:-}" ]]; then
  return 0
fi
export DATALAB_COMMON_LOADED=1

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
  KAFKA_ZK_DATA_DIR="${KAFKA_BASE}/zookeeper-data"
  HADOOP_LOG_DIR="${RUNTIME_ROOT}/hadoop/logs"
  YARN_LOG_DIR="${RUNTIME_ROOT}/hadoop/logs/yarn"
  MAPRED_LOG_DIR="${RUNTIME_ROOT}/hadoop/logs/mapred"
  AIRFLOW_PID_DIR="${RUNTIME_ROOT}/airflow/pids"

  mkdir -p \
    "${HIVE_LOG_DIR}" \
    "${HIVE_PID_DIR}" \
    "${KAFKA_LOG_DIR}" \
    "${KAFKA_PID_DIR}" \
    "${AIRFLOW_PID_DIR}"

  APP_BIN_DIR="${WORKSPACE}/app/bin"
  mkdir -p "${APP_BIN_DIR}"

  export APP_BIN_DIR HDFS_BASE HDFS_NAME_DIR HDFS_DATA_DIR \
    SPARK_PID_DIR SPARK_LOG_DIR SPARK_EVENTS_DIR SPARK_WAREHOUSE_DIR \
    HIVE_METASTORE_DB HIVE_WAREHOUSE HIVE_PID_DIR HIVE_LOG_DIR \
    KAFKA_BASE KAFKA_PID_DIR KAFKA_LOG_DIR KAFKA_ZK_DATA_DIR \
    HADOOP_LOG_DIR YARN_LOG_DIR MAPRED_LOG_DIR AIRFLOW_PID_DIR
}

common::init_workdir

: "${SPARK_HOME:=/opt/spark}"
: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_MAPRED_HOME:=${HADOOP_HOME}}"
: "${HIVE_HOME:=/opt/hive}"
: "${KAFKA_HOME:=/opt/kafka}"
: "${HIVE_SERVER2_THRIFT_PORT:=10000}"
: "${HIVE_SERVER2_THRIFT_HOST:=0.0.0.0}"
: "${HIVE_SERVER2_HTTP_PORT:=10001}"
: "${HIVE_SERVER2_HTTP_PATH:=cliservice}"

SPARK_HOME="$(strip_cr "${SPARK_HOME}")"
HADOOP_HOME="$(strip_cr "${HADOOP_HOME}")"
HADOOP_MAPRED_HOME="$(strip_cr "${HADOOP_MAPRED_HOME}")"
HIVE_HOME="$(strip_cr "${HIVE_HOME}")"
KAFKA_HOME="$(strip_cr "${KAFKA_HOME}")"
HIVE_SERVER2_THRIFT_PORT="$(strip_cr "${HIVE_SERVER2_THRIFT_PORT}")"
HIVE_SERVER2_THRIFT_HOST="$(strip_cr "${HIVE_SERVER2_THRIFT_HOST}")"
HIVE_SERVER2_HTTP_PORT="$(strip_cr "${HIVE_SERVER2_HTTP_PORT}")"
HIVE_SERVER2_HTTP_PATH="$(strip_cr "${HIVE_SERVER2_HTTP_PATH}")"

export SPARK_HOME HADOOP_HOME HADOOP_MAPRED_HOME HIVE_HOME KAFKA_HOME \
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
export YARN_CONF_DIR="${HADOOP_HOME}/etc/hadoop"
case ":$PATH:" in
  *":${JAVA_HOME}/bin:"*) ;;
  *) export PATH="${PATH}:${JAVA_HOME}/bin" ;;
esac

case ":$PATH:" in
  *":${APP_BIN_DIR}:"*) ;;
  *) export PATH="${APP_BIN_DIR}:$PATH" ;;
esac

common::ensure_cli_shortcuts() {
  local rc_file="${HOME}/.bashrc"
  local export_line='export PATH="$HOME/app/bin:$PATH"'
  local hive_alias="alias hive='bash \"${HOME}/app/scripts/hive/cli.sh\"'"
  local profile_file="${HOME}/.profile"

  if [ ! -e "${rc_file}" ]; then
    printf '# Data Lab CLI shortcuts\n%s\n%s\n' "${export_line}" "${hive_alias}" > "${rc_file}" 2>/dev/null || true
    return
  fi

  if [ -w "${rc_file}" ] && ! grep -Fq 'app/bin' "${rc_file}" 2>/dev/null; then
    printf '\n# Data Lab CLI shortcuts\n%s\n' "${export_line}" >> "${rc_file}" 2>/dev/null || true
  fi

  if [ -w "${rc_file}" ] && ! grep -Fq "${hive_alias}" "${rc_file}" 2>/dev/null; then
    printf '%s\n' "${hive_alias}" >> "${rc_file}" 2>/dev/null || true
  fi

  # Ensure login shells also pick up the alias/PATH
  if [ ! -e "${profile_file}" ]; then
    printf '%s\n%s\n' "${export_line}" "${hive_alias}" > "${profile_file}" 2>/dev/null || true
  else
    if [ -w "${profile_file}" ] && ! grep -Fq 'app/bin' "${profile_file}" 2>/dev/null; then
      printf '%s\n' "${export_line}" >> "${profile_file}" 2>/dev/null || true
    fi
    if [ -w "${profile_file}" ] && ! grep -Fq "${hive_alias}" "${profile_file}" 2>/dev/null; then
      printf '%s\n' "${hive_alias}" >> "${profile_file}" 2>/dev/null || true
    fi
  fi
}

common::ensure_cli_shortcuts

export SPARK_PID_DIR SPARK_LOG_DIR SPARK_EVENTS_DIR
export SPARK_HISTORY_OPTS="-Dspark.history.fs.logDirectory=file://${SPARK_EVENTS_DIR}"
export HADOOP_LOG_DIR YARN_LOG_DIR MAPRED_LOG_DIR
export HIVE_PID_DIR
export _HIVE_PID_DIR="${HIVE_PID_DIR}"
export HIVE_SERVER2_PID_DIR="${HIVE_PID_DIR}"
export HIVE_METASTORE_PID_DIR="${HIVE_PID_DIR}"
export HIVESERVER2_PID_DIR="${HIVE_PID_DIR}"
export METASTORE_PID_DIR="${HIVE_PID_DIR}"
export HIVE_LOG_DIR
export HIVE_CONF_DIR="${HIVE_HOME}/conf"

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
