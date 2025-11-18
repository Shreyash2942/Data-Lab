#!/usr/bin/env bash
# Misc service helpers (Spark/Kafka/Airflow) until they get their own modules.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

services::ensure_spark_dirs() {
  mkdir -p "${SPARK_PID_DIR}" "${SPARK_LOG_DIR}" "${SPARK_EVENTS_DIR}" "${SPARK_WAREHOUSE_DIR}"
}

services::start_spark_cluster() {
  services::ensure_spark_dirs
  echo "[*] Starting Spark master, worker, and history server..."
  bash "${SPARK_HOME}/sbin/start-master.sh"
  bash "${SPARK_HOME}/sbin/start-worker.sh" "spark://localhost:7077"
  bash "${SPARK_HOME}/sbin/start-history-server.sh"
  echo "Spark master UI: http://localhost:9090  |  History UI: http://localhost:18080"
}

services::stop_spark_cluster() {
  echo "[*] Stopping Spark master, worker, and history server..."
  bash "${SPARK_HOME}/sbin/stop-history-server.sh" || true
  bash "${SPARK_HOME}/sbin/stop-worker.sh" || true
  bash "${SPARK_HOME}/sbin/stop-master.sh" || true
}

services::ensure_kafka_dirs() {
  mkdir -p "${KAFKA_PID_DIR}" "${KAFKA_LOG_DIR}" "${KAFKA_ZK_DATA_DIR}"
}

services::start_kafka() {
  services::ensure_kafka_dirs
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
    sleep 3
  else
    echo "[*] Kafka already running (PID $(cat "${KAFKA_PID_DIR}/kafka.pid"))."
  fi
  echo "Kafka broker listening on localhost:9092"
}

services::stop_kafka() {
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

services::start_airflow() {
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

services::stop_airflow() {
  if [ -f "${AIRFLOW_PID_DIR}/webserver.pid" ]; then
    kill "$(cat "${AIRFLOW_PID_DIR}/webserver.pid}")" || true
    rm -f "${AIRFLOW_PID_DIR}/webserver.pid"
  else
    pkill -f "airflow webserver" || true
  fi
  if [ -f "${AIRFLOW_PID_DIR}/scheduler.pid" ]; then
    kill "$(cat "${AIRFLOW_PID_DIR}/scheduler.pid}")" || true
    rm -f "${AIRFLOW_PID_DIR}/scheduler.pid"
  else
    pkill -f "airflow scheduler" || true
  fi
  echo "Airflow services stopped."
}
