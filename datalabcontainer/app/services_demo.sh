#!/usr/bin/env bash
set -e

if [ -z "${BASH_VERSION:-}" ]; then
  echo "This script must be run with bash (try: bash services_demo.sh)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVICE_NAME="${SERVICE_NAME:-data-lab}"
CONTAINER_NAME="${CONTAINER_NAME:-datalab}"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
source "${SCRIPT_DIR}/scripts/host_exec.sh"

datalab::ensure_inside_or_exec "${REPO_ROOT}" "${SERVICE_NAME}" "${CONTAINER_NAME}" "/home/datalab/app/${SCRIPT_NAME}" "$@"

strip_cr() {
  local value="${1:-}"
  value="${value//$'\r'/}"
  printf '%s' "${value}"
}

HOME_DIR="$(strip_cr "${HOME:-/home/datalab}")"
WORKSPACE="$(strip_cr "${WORKSPACE:-${HOME_DIR}}")"
RUNTIME_ROOT="$(strip_cr "${RUNTIME_ROOT:-${WORKSPACE}/runtime}")"
mkdir -p "${RUNTIME_ROOT}"

: "${SPARK_HOME:=/opt/spark}"
: "${HADOOP_HOME:=/opt/hadoop}"
: "${HIVE_HOME:=/opt/hive}"
: "${KAFKA_HOME:=/opt/kafka}"
SPARK_HOME="$(strip_cr "${SPARK_HOME}")"
HADOOP_HOME="$(strip_cr "${HADOOP_HOME}")"
HIVE_HOME="$(strip_cr "${HIVE_HOME}")"
KAFKA_HOME="$(strip_cr "${KAFKA_HOME}")"
POSTGRES_PORT="$(strip_cr "${POSTGRES_PORT:-5432}")"
POSTGRES_DB="$(strip_cr "${POSTGRES_DB:-datalab}")"
POSTGRES_USER="$(strip_cr "${POSTGRES_USER:-datalab}")"
POSTGRES_PASSWORD="$(strip_cr "${POSTGRES_PASSWORD:-datalab}")"
MONGO_PORT="$(strip_cr "${MONGO_PORT:-27017}")"
MONGO_DB="$(strip_cr "${MONGO_DB:-datalab}")"
MONGO_ROOT_USERNAME="$(strip_cr "${MONGO_ROOT_USERNAME:-datalab}")"
MONGO_ROOT_PASSWORD="$(strip_cr "${MONGO_ROOT_PASSWORD:-datalab}")"
MONGO_AUTH_ENABLED="$(strip_cr "${MONGO_AUTH_ENABLED:-true}")"
REDIS_PORT="$(strip_cr "${REDIS_PORT:-6379}")"

HADOOP_BIN="${HADOOP_HOME}/bin/hadoop"
HIVE_BIN="${HIVE_HOME}/bin/hive"

run_python_example() {
  python "${WORKSPACE}/python/example.py"
}

run_spark_example() {
  python "${WORKSPACE}/spark/example_pyspark.py"
}

run_dbt_project() {
  (
    cd "${WORKSPACE}/dbt"
    dbt debug && dbt run
  )
}

run_kafka_demo() {
  bash "${WORKSPACE}/kafka/demo.sh"
}

run_java_example() {
  javac "${WORKSPACE}/java/Example.java"
  java -cp "${WORKSPACE}/java" Example
}

run_scala_example() {
  scalac "${WORKSPACE}/scala/example.scala"
  scala -cp "${WORKSPACE}/scala" HelloDataLab
}

run_terraform_demo() {
  mkdir -p "${RUNTIME_ROOT}/terraform"
  export TF_DATA_DIR="${RUNTIME_ROOT}/terraform/.terraform"
  terraform -chdir="${WORKSPACE}/terraform" init
  terraform -chdir="${WORKSPACE}/terraform" apply -auto-approve -state="${RUNTIME_ROOT}/terraform/terraform.tfstate"
}

check_airflow() {
  airflow version || echo "Airflow check failed."
}

check_hadoop() {
  "${HADOOP_BIN}" version || echo "Hadoop version failed."
}

check_hive_cli() {
  "${HIVE_BIN}" -e 'SHOW DATABASES;' || echo "Hive CLI failed."
}

run_hudi_demo() {
  python "${WORKSPACE}/hudi/hudi_example.py"
}

run_iceberg_demo() {
  python "${WORKSPACE}/iceberg/iceberg_example.py"
}

run_delta_demo() {
  python "${WORKSPACE}/delta/delta_example.py"
}

run_postgres_demo() {
  PGPASSWORD="${POSTGRES_PASSWORD}" \
  psql -h localhost -p "${POSTGRES_PORT}" -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -f "${WORKSPACE}/postgres/example_postgres.sql"
}

run_mongodb_demo() {
  MONGO_PORT="${MONGO_PORT}" \
  MONGO_DB="${MONGO_DB}" \
  MONGO_ROOT_USERNAME="${MONGO_ROOT_USERNAME}" \
  MONGO_ROOT_PASSWORD="${MONGO_ROOT_PASSWORD}" \
  MONGO_AUTH_ENABLED="${MONGO_AUTH_ENABLED}" \
  python "${WORKSPACE}/mongodb/example_mongodb.py"
}

run_redis_demo() {
  REDIS_PORT="${REDIS_PORT}" python "${WORKSPACE}/redis/example_redis.py"
}

run_hdfs_smoke_test() {
  bash "${WORKSPACE}/hadoop/scripts/hdfs_check.sh"
}

setup_hive_demo_databases() {
  bash "${WORKSPACE}/hive/bootstrap_demo.sh"
}

run_all_demos() {
  echo "[*] Running Python example..."
  run_python_example || echo "Python example failed."

  echo "[*] Running Spark example..."
  run_spark_example || echo "Spark example failed."

  echo "[*] Checking Airflow..."
  check_airflow || true

  echo "[*] Running dbt debug/run..."
  run_dbt_project || echo "dbt project failed."

  echo "[*] Checking Hadoop..."
  check_hadoop || true

  echo "[*] Running HDFS smoke test..."
  run_hdfs_smoke_test || echo "HDFS smoke test failed."

  echo "[*] Running Hive CLI..."
  check_hive_cli || true

  echo "[*] Creating Hive demo databases..."
  setup_hive_demo_databases || echo "Hive demo setup failed."

  echo "[*] Running Kafka demo..."
  run_kafka_demo || echo "Kafka demo failed."

  echo "[*] Running Java example..."
  run_java_example || echo "Java example failed."

  echo "[*] Running Scala example..."
  run_scala_example || echo "Scala example failed."

  echo "[*] Running Terraform demo..."
  run_terraform_demo || echo "Terraform demo failed."

  echo "[*] Running PostgreSQL demo..."
  run_postgres_demo || echo "PostgreSQL demo failed."

  echo "[*] Running MongoDB demo..."
  run_mongodb_demo || echo "MongoDB demo failed."

  echo "[*] Running Redis demo..."
  run_redis_demo || echo "Redis demo failed."

  echo "[+] Demo run completed."
}

handle_cli_flag() {
  case "$1" in
    --run-python-example) run_python_example; exit 0 ;;
    --run-spark-example) run_spark_example; exit 0 ;;
    --run-dbt-project) run_dbt_project; exit 0 ;;
    --run-kafka-demo) run_kafka_demo; exit 0 ;;
    --run-java-example) run_java_example; exit 0 ;;
    --run-scala-example) run_scala_example; exit 0 ;;
    --run-terraform-demo) run_terraform_demo; exit 0 ;;
    --check-airflow) check_airflow; exit 0 ;;
    --check-hadoop) check_hadoop; exit 0 ;;
    --check-hive) check_hive_cli; exit 0 ;;
    --run-hudi-demo) run_hudi_demo; exit 0 ;;
    --run-iceberg-demo) run_iceberg_demo; exit 0 ;;
    --run-delta-demo) run_delta_demo; exit 0 ;;
    --run-hdfs-check) run_hdfs_smoke_test; exit 0 ;;
    --setup-hive-demo) setup_hive_demo_databases; exit 0 ;;
    --run-postgres-demo) run_postgres_demo; exit 0 ;;
    --run-mongodb-demo) run_mongodb_demo; exit 0 ;;
    --run-redis-demo) run_redis_demo; exit 0 ;;
    --run-all-demos) run_all_demos; exit 0 ;;
  esac
}

handle_cli_flag "$1"

echo "=== Data Lab :: DEMO MENU ==="
echo "1) Python example"
echo "2) Spark example"
echo "3) dbt project"
echo "4) Kafka demo"
echo "5) Java example"
echo "6) Scala example"
echo "7) Terraform demo"
echo "8) Airflow version check"
echo "9) Hadoop version check"
echo "10) Hive CLI check"
echo "11) Run all demos/checks"
echo "12) Hudi demo"
echo "13) Iceberg demo"
echo "14) Delta Lake demo"
echo "15) HDFS smoke test (upload + list sample file)"
echo "16) Hive demo databases (create + show tables)"
echo "17) PostgreSQL demo"
echo "18) MongoDB demo"
echo "19) Redis demo"
echo "0) Exit"
read -p "Select option: " opt

case "$opt" in
  1) run_python_example ;;
  2) run_spark_example ;;
  3) run_dbt_project ;;
  4) run_kafka_demo ;;
  5) run_java_example ;;
  6) run_scala_example ;;
  7) run_terraform_demo ;;
  8) check_airflow ;;
  9) check_hadoop ;;
  10) check_hive_cli ;;
  11) run_all_demos ;;
  12) run_hudi_demo ;;
  13) run_iceberg_demo ;;
  14) run_delta_demo ;;
  15) run_hdfs_smoke_test ;;
  16) setup_hive_demo_databases ;;
  17) run_postgres_demo ;;
  18) run_mongodb_demo ;;
  19) run_redis_demo ;;
  0) echo "Bye." ;;
  *) echo "Invalid option."; exit 1 ;;
esac
