#!/usr/bin/env bash
set -e

WORKSPACE=/workspace
HDFS_BASE="${WORKSPACE}/hadoop/dfs"
HDFS_NAME_DIR="${HDFS_BASE}/name"
HDFS_DATA_DIR="${HDFS_BASE}/data"
SPARK_PID_DIR="${WORKSPACE}/spark/pids"
SPARK_LOG_DIR="${WORKSPACE}/spark/logs"
SPARK_EVENTS_DIR="${WORKSPACE}/spark/events"
HIVE_METASTORE_DB="${WORKSPACE}/hive/metastore_db"
HIVE_WAREHOUSE="${WORKSPACE}/hive/warehouse"
HIVE_PID_DIR="${WORKSPACE}/hive/pids"
KAFKA_BASE="${WORKSPACE}/kafka"
KAFKA_PID_DIR="${KAFKA_BASE}/pids"
KAFKA_LOG_DIR="${KAFKA_BASE}/logs"
KAFKA_ZK_DATA_DIR="${KAFKA_BASE}/zookeeper-data"

ensure_hadoop_dirs() {
  mkdir -p "${HDFS_NAME_DIR}" "${HDFS_DATA_DIR}" "${WORKSPACE}/hadoop/tmp"
}

format_namenode_if_needed() {
  if [ ! -f "${HDFS_NAME_DIR}/current/VERSION" ]; then
    echo "[*] Formatting NameNode (first-run)..."
    hdfs namenode -format -force -nonInteractive
  fi
}

start_hadoop_services() {
  ensure_hadoop_dirs
  format_namenode_if_needed
  echo "[*] Starting Hadoop daemons..."
  hdfs --daemon start namenode
  hdfs --daemon start datanode
  yarn --daemon start resourcemanager
  yarn --daemon start nodemanager
  mapred --daemon start historyserver || true
  jps
  echo "HDFS UI: http://localhost:9870  |  YARN UI: http://localhost:8088"
}

stop_hadoop_services() {
  echo "[*] Stopping Hadoop daemons..."
  mapred --daemon stop historyserver || true
  yarn --daemon stop nodemanager || true
  yarn --daemon stop resourcemanager || true
  hdfs --daemon stop datanode || true
  hdfs --daemon stop namenode || true
}

ensure_spark_dirs() {
  mkdir -p "${SPARK_PID_DIR}" "${SPARK_LOG_DIR}" "${SPARK_EVENTS_DIR}" "${WORKSPACE}/spark/warehouse"
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
  mkdir -p "${HIVE_METASTORE_DB}" "${HIVE_WAREHOUSE}" "${HIVE_PID_DIR}" "${WORKSPACE}/hive/tmp"
}

init_hive_metastore_if_needed() {
  if [ ! -f "${HIVE_METASTORE_DB}/service.properties" ]; then
    echo "[*] Initializing Hive metastore (Derby)..."
    schematool -dbType derby -initSchema -force || true
  fi
}

start_hive_services() {
  ensure_hive_dirs
  init_hive_metastore_if_needed
  echo "[*] Starting Hive metastore..."
  nohup hive --service metastore > "${HIVE_PID_DIR}/metastore.log" 2>&1 &
  echo $! > "${HIVE_PID_DIR}/metastore.pid"
  echo "[*] Starting HiveServer2..."
  nohup hive --service hiveserver2 > "${HIVE_PID_DIR}/hiveserver2.log" 2>&1 &
  echo $! > "${HIVE_PID_DIR}/hiveserver2.pid"
  echo "HiveServer2 JDBC: jdbc:hive2://localhost:10000 (user: datalab_user)"
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

start_data_services() {
  start_spark_cluster
  start_hadoop_services
  start_hive_services
  start_kafka_services
  echo "✅ Spark, Hadoop, Hive, and Kafka services started."
}

stop_data_services() {
  stop_kafka_services || true
  stop_hive_services
  stop_hadoop_services
  stop_spark_cluster
  echo "🛑 Spark, Hadoop, Hive, and Kafka services stopped."
}

run_all_techstack_demos() {
  echo "[*] Running Python example..."
  python "${WORKSPACE}/python/example.py" || echo "Python example failed."

  echo "[*] Running Spark example..."
  python "${WORKSPACE}/spark/example_pyspark.py" || echo "Spark example failed."

  echo "[*] Checking Airflow..."
  airflow version || echo "Airflow check failed."

  echo "[*] Running dbt debug..."
  (cd "${WORKSPACE}/dbt" && dbt debug) || echo "dbt debug failed."

  echo "[*] Checking Hadoop..."
  hadoop version || echo "Hadoop version failed."

  echo "[*] Running Hive CLI..."
  hive -e 'SHOW DATABASES;' || echo "Hive CLI failed."

  echo "[*] Running Kafka demo..."
  bash "${WORKSPACE}/kafka/demo.sh" || echo "Kafka demo failed."

  echo "[*] Running Java example..."
  javac "${WORKSPACE}/java/Example.java" && java -cp "${WORKSPACE}/java" Example || echo "Java example failed."

  echo "[*] Running Scala example..."
  scalac "${WORKSPACE}/scala/example.scala" && scala -cp "${WORKSPACE}/scala" HelloDataLab || echo "Scala example failed."

  echo "[*] Running Terraform demo..."
  terraform -chdir="${WORKSPACE}/terraform" init -input=false >/dev/null || true
  terraform -chdir="${WORKSPACE}/terraform" apply -auto-approve || echo "Terraform apply failed."

  echo "✅ Completed tech stack demo run."
}

case "$1" in
  --start-core)
    start_data_services
    exit 0
    ;;
  --stop-core)
    stop_data_services
    exit 0
    ;;
  --restart-core)
    stop_data_services || true
    start_data_services
    exit 0
    ;;
  --run-all-demos)
    run_all_techstack_demos
    exit 0
    ;;
esac

echo "=== Data Lab :: TECH STACK MENU ==="
echo "1) Python example"
echo "2) Spark session"
echo "3) Start Spark/Hadoop/Hive services"
echo "4) Airflow webserver & scheduler"
echo "5) dbt project"
echo "6) Hive CLI"
echo "7) Kafka demo"
echo "8) Java example"
echo "9) Scala example"
echo "10) Terraform init/apply"
echo "11) Run all tech stack demos/checks"
echo "0) Exit"
read -p "Select option: " opt

case "$opt" in
  1)
    python "${WORKSPACE}/python/example.py"
    ;;
  2)
    python "${WORKSPACE}/spark/example_pyspark.py"
    ;;
  3)
    start_data_services
    ;;
  4)
    airflow db init || true
    airflow webserver -p 8080 &
    airflow scheduler &
    echo "Airflow webserver: http://localhost:8080"
    echo "Default admin (create once if missing): airflow users create --username admin --password admin --firstname Data --lastname Lab --role Admin --email admin@example.com"
    ;;
  5)
    cd "${WORKSPACE}/dbt"
    dbt debug && dbt run
    ;;
  6)
    hive -e 'SHOW DATABASES;' || echo "Hive CLI running without metastore (demo)."
    ;;
  7)
    bash "${WORKSPACE}/kafka/demo.sh"
    ;;
  8)
    javac "${WORKSPACE}/java/Example.java"
    java -cp "${WORKSPACE}/java" Example
    ;;
  9)
    scalac "${WORKSPACE}/scala/example.scala"
    scala -cp "${WORKSPACE}/scala" HelloDataLab
    ;;
  10)
    terraform -chdir="${WORKSPACE}/terraform" init
    terraform -chdir="${WORKSPACE}/terraform" apply -auto-approve
    ;;
  11)
    run_all_techstack_demos
    ;;
  0)
    echo "Bye."
    ;;
  *)
    echo "Invalid option."
    exit 1
    ;;
esac
