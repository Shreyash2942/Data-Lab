#!/usr/bin/env bash
set -e

if [ -z "${BASH_VERSION:-}" ]; then
  echo "This script must be run with bash (try: bash services_start.sh)." >&2
  exit 1
fi

HOME_DIR="${HOME:-/home/datalab}"
WORKSPACE="${WORKSPACE:-${HOME_DIR}}"
RUNTIME_ROOT="${RUNTIME_ROOT:-${WORKSPACE}/runtime}"
mkdir -p "${RUNTIME_ROOT}"

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
KAFKA_BASE="${RUNTIME_ROOT}/kafka"
KAFKA_PID_DIR="${KAFKA_BASE}/pids"
KAFKA_LOG_DIR="${KAFKA_BASE}/logs"
KAFKA_ZK_DATA_DIR="${KAFKA_BASE}/zookeeper-data"
HADOOP_LOG_DIR="${RUNTIME_ROOT}/hadoop/logs"
YARN_LOG_DIR="${RUNTIME_ROOT}/hadoop/logs/yarn"
MAPRED_LOG_DIR="${RUNTIME_ROOT}/hadoop/logs/mapred"
AIRFLOW_PID_DIR="${RUNTIME_ROOT}/airflow/pids"

: "${SPARK_HOME:=/opt/spark}"
: "${HADOOP_HOME:=/opt/hadoop}"
: "${HIVE_HOME:=/opt/hive}"
: "${KAFKA_HOME:=/opt/kafka}"

HDFS_BIN="${HADOOP_HOME}/bin/hdfs"
YARN_BIN="${HADOOP_HOME}/bin/yarn"
MAPRED_BIN="${HADOOP_HOME}/bin/mapred"
HADOOP_BIN="${HADOOP_HOME}/bin/hadoop"
HIVE_BIN="${HIVE_HOME}/bin/hive"
SCHEMATOOL_BIN="${HIVE_HOME}/bin/schematool"

: "${JAVA_HOME:=/usr/lib/jvm/java-11-openjdk-amd64}"
export JAVA_HOME
case ":$PATH:" in
  *":${JAVA_HOME}/bin:"*) ;;
  *) export PATH="${PATH}:${JAVA_HOME}/bin" ;;
esac

export SPARK_PID_DIR SPARK_LOG_DIR SPARK_EVENTS_DIR
export SPARK_HISTORY_OPTS="-Dspark.history.fs.logDirectory=file://${SPARK_EVENTS_DIR}"
export HADOOP_LOG_DIR YARN_LOG_DIR MAPRED_LOG_DIR

is_hadoop_running() {
  pgrep -f NameNode >/dev/null 2>&1 && pgrep -f ResourceManager >/dev/null 2>&1
}

ensure_hadoop_dirs() {
  mkdir -p \
    "${HDFS_NAME_DIR}" \
    "${HDFS_DATA_DIR}" \
    "${RUNTIME_ROOT}/hadoop/tmp" \
    "${HADOOP_LOG_DIR}" \
    "${YARN_LOG_DIR}" \
    "${MAPRED_LOG_DIR}"
}

format_namenode_if_needed() {
  if [ ! -f "${HDFS_NAME_DIR}/current/VERSION" ]; then
    echo "[*] Formatting NameNode (first-run)..."
    "${HDFS_BIN}" namenode -format -force -nonInteractive
  fi
}

start_hadoop_services() {
  ensure_hadoop_dirs
  format_namenode_if_needed
  echo "[*] Starting Hadoop daemons..."
  "${HDFS_BIN}" --daemon start namenode
  "${HDFS_BIN}" --daemon start datanode
  "${YARN_BIN}" --daemon start resourcemanager
  "${YARN_BIN}" --daemon start nodemanager
  "${MAPRED_BIN}" --daemon start historyserver || true
  jps
  echo "HDFS UI: http://localhost:9870  |  YARN UI: http://localhost:8088"
}

stop_hadoop_services() {
  echo "[*] Stopping Hadoop daemons..."
  "${MAPRED_BIN}" --daemon stop historyserver || true
  "${YARN_BIN}" --daemon stop nodemanager || true
  "${YARN_BIN}" --daemon stop resourcemanager || true
  "${HDFS_BIN}" --daemon stop datanode || true
  "${HDFS_BIN}" --daemon stop namenode || true
}

ensure_hadoop_running() {
  if is_hadoop_running; then
    echo "[*] Hadoop already running."
    return
  fi
  echo "[*] Hadoop not running; starting now..."
  start_hadoop_services
  echo "[*] Waiting for Hadoop services to stabilize..."
  sleep 5
}

ensure_spark_dirs() {
  mkdir -p "${SPARK_PID_DIR}" "${SPARK_LOG_DIR}" "${SPARK_EVENTS_DIR}" "${SPARK_WAREHOUSE_DIR}"
}

start_spark_cluster() {
  ensure_spark_dirs
  echo "[*] Starting Spark master, worker, and history server..."
  bash "${SPARK_HOME}/sbin/start-master.sh"
  bash "${SPARK_HOME}/sbin/start-worker.sh" "spark://localhost:7077"
  bash "${SPARK_HOME}/sbin/start-history-server.sh"
  echo "Spark master UI: http://localhost:9090  |  History UI: http://localhost:18080"
}

stop_spark_cluster() {
  echo "[*] Stopping Spark services..."
  bash "${SPARK_HOME}/sbin/stop-history-server.sh" || true
  bash "${SPARK_HOME}/sbin/stop-worker.sh" || true
  bash "${SPARK_HOME}/sbin/stop-master.sh" || true
}

ensure_hive_dirs() {
  mkdir -p "${HIVE_METASTORE_DB}" "${HIVE_WAREHOUSE}" "${HIVE_PID_DIR}" "${RUNTIME_ROOT}/hive/tmp"
}

init_hive_metastore_if_needed() {
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

start_hive_services() {
  ensure_hive_dirs
  init_hive_metastore_if_needed
  echo "[*] Starting Hive metastore..."
  nohup "${HIVE_BIN}" --service metastore > "${HIVE_PID_DIR}/metastore.log" 2>&1 &
  echo $! > "${HIVE_PID_DIR}/metastore.pid"
  echo "[*] Starting HiveServer2..."
  nohup "${HIVE_BIN}" --service hiveserver2 > "${HIVE_PID_DIR}/hiveserver2.log" 2>&1 &
  echo $! > "${HIVE_PID_DIR}/hiveserver2.pid"
  echo "HiveServer2 JDBC: jdbc:hive2://localhost:10000 (user: datalab)"
}

stop_hive_services() {
  echo "[*] Stopping Hive services..."
  if [ -f "${HIVE_PID_DIR}/hiveserver2.pid" ]; then
    kill "$(cat "${HIVE_PID_DIR}/hiveserver2.pid")" || true
    rm -f "${HIVE_PID_DIR}/hiveserver2.pid"
  else
    pkill -f HiveServer2 || true
  fi
  if [ -f "${HIVE_PID_DIR}/metastore.pid" ]; then
    kill "$(cat "${HIVE_PID_DIR}/metastore.pid")" || true
    rm -f "${HIVE_PID_DIR}/metastore.pid"
  else
    pkill -f HiveMetaStore || true
  fi
}

ensure_kafka_dirs() {
  mkdir -p "${KAFKA_PID_DIR}" "${KAFKA_LOG_DIR}" "${KAFKA_ZK_DATA_DIR}"
}

start_kafka_services() {
  ensure_kafka_dirs
  if [ ! -f "${KAFKA_PID_DIR}/zookeeper.pid" ] || ! kill -0 "$(cat "${KAFKA_PID_DIR}/zookeeper.pid" 2>/dev/null)" 2>/dev/null; then
    echo "[*] Starting Zookeeper..."
    nohup "${KAFKA_HOME}/bin/zookeeper-server-start.sh" "${KAFKA_HOME}/config/zookeeper.properties" > "${KAFKA_LOG_DIR}/zookeeper.log" 2>&1 &
    echo $! > "${KAFKA_PID_DIR}/zookeeper.pid"
    sleep 5
  else
    echo "[*] Zookeeper already running (PID $(cat "${KAFKA_PID_DIR}/zookeeper.pid"))."
  fi

  if [ ! -f "${KAFKA_PID_DIR}/kafka.pid" ] || ! kill -0 "$(cat "${KAFKA_PID_DIR}/kafka.pid" 2>/dev/null)" 2>/dev/null; then
    echo "[*] Starting Kafka broker..."
    nohup "${KAFKA_HOME}/bin/kafka-server-start.sh" "${KAFKA_HOME}/config/server.properties" > "${KAFKA_LOG_DIR}/kafka.log" 2>&1 &
    echo $! > "${KAFKA_PID_DIR}/kafka.pid"
    sleep 5
  else
    echo "[*] Kafka broker already running (PID $(cat "${KAFKA_PID_DIR}/kafka.pid"))."
  fi
  echo "Kafka broker: PLAINTEXT://localhost:9092"
}

stop_kafka_services() {
  echo "[*] Stopping Kafka services..."
  if [ -f "${KAFKA_PID_DIR}/kafka.pid" ]; then
    kill "$(cat "${KAFKA_PID_DIR}/kafka.pid")" || true
    rm -f "${KAFKA_PID_DIR}/kafka.pid"
  else
    "${KAFKA_HOME}/bin/kafka-server-stop.sh" || true
  fi
  if [ -f "${KAFKA_PID_DIR}/zookeeper.pid" ]; then
    kill "$(cat "${KAFKA_PID_DIR}/zookeeper.pid")" || true
    rm -f "${KAFKA_PID_DIR}/zookeeper.pid"
  else
    "${KAFKA_HOME}/bin/zookeeper-server-stop.sh" || true
  fi
}

start_airflow_services() {
  mkdir -p "${AIRFLOW_PID_DIR}"
  airflow db init || true
  echo "[*] Starting Airflow webserver..."
  airflow webserver -p 8080 > "${AIRFLOW_PID_DIR}/webserver.log" 2>&1 &
  echo $! > "${AIRFLOW_PID_DIR}/webserver.pid"
  echo "[*] Starting Airflow scheduler..."
  airflow scheduler > "${AIRFLOW_PID_DIR}/scheduler.log" 2>&1 &
  echo $! > "${AIRFLOW_PID_DIR}/scheduler.pid"
  echo "Airflow webserver: http://localhost:8080"
}

stop_airflow_services() {
  if [ -f "${AIRFLOW_PID_DIR}/webserver.pid" ]; then
    kill "$(cat "${AIRFLOW_PID_DIR}/webserver.pid")" || true
    rm -f "${AIRFLOW_PID_DIR}/webserver.pid"
  else
    pkill -f "airflow webserver" || true
  fi
  if [ -f "${AIRFLOW_PID_DIR}/scheduler.pid" ]; then
    kill "$(cat "${AIRFLOW_PID_DIR}/scheduler.pid")" || true
    rm -f "${AIRFLOW_PID_DIR}/scheduler.pid"
  else
    pkill -f "airflow scheduler" || true
  fi
  echo "Airflow services stopped."
}

start_data_services() {
  ensure_hadoop_running
  start_spark_cluster
  start_hive_services
  start_kafka_services
  echo "[+] Spark, Hadoop, Hive, and Kafka services started."
}

stop_data_services() {
  stop_kafka_services || true
  stop_hive_services
  stop_hadoop_services
  stop_spark_cluster
  echo "[+] Spark, Hadoop, Hive, and Kafka services stopped."
}

handle_cli_flag() {
  case "$1" in
    --start-spark) start_spark_cluster; exit 0 ;;
    --stop-spark) stop_spark_cluster; exit 0 ;;
    --start-hadoop) start_hadoop_services; exit 0 ;;
    --stop-hadoop) stop_hadoop_services; exit 0 ;;
    --start-hive)
      ensure_hadoop_running
      start_hive_services
      exit 0
      ;;
    --stop-hive) stop_hive_services; exit 0 ;;
    --start-kafka) start_kafka_services; exit 0 ;;
    --stop-kafka) stop_kafka_services; exit 0 ;;
    --start-airflow) start_airflow_services; exit 0 ;;
    --stop-airflow) stop_airflow_services; exit 0 ;;
    --start-core) start_data_services; exit 0 ;;
    --stop-core) stop_data_services; exit 0 ;;
    --restart-core)
      stop_data_services || true
      start_data_services
      exit 0
      ;;
  esac
}

handle_cli_flag "$1"

echo "=== Data Lab :: START MENU ==="
echo "1) Start Spark services"
echo "2) Start Hadoop services"
echo "3) Start Hive services"
echo "4) Start Kafka services"
echo "5) Start Airflow webserver & scheduler"
echo "6) Start ALL core services (Spark/Hadoop/Hive/Kafka)"
echo "0) Exit"
read -p "Select option: " opt

case "$opt" in
  1)
    start_spark_cluster
    ;;
  2)
    start_hadoop_services
    ;;
  3)
    ensure_hadoop_running
    start_hive_services
    ;;
  4)
    start_kafka_services
    ;;
  5)
    start_airflow_services
    ;;
  6)
    start_data_services
    ;;
  0)
    echo "Bye."
    ;;
  *)
    echo "Invalid option."
    exit 1
    ;;
esac
