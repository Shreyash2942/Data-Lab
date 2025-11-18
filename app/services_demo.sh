#!/usr/bin/env bash
set -e

if [ -z "${BASH_VERSION:-}" ]; then
  echo "This script must be run with bash (try: bash services_demo.sh)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SERVICE_NAME="${SERVICE_NAME:-data-lab}"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

if [ ! -f "/.dockerenv" ] && [ -z "${INSIDE_DATALAB:-}" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Please run this script inside the data-lab container (e.g. `docker compose exec data-lab bash`)
or install Docker CLI so it can exec into the container automatically.
EOF
    exit 1
  fi
  (
    cd "${REPO_ROOT}"
    docker compose exec -e INSIDE_DATALAB=1 "${SERVICE_NAME}" "/home/datalab/app/${SCRIPT_NAME}" "$@"
  )
  exit $?
fi

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
  0) echo "Bye." ;;
  *) echo "Invalid option."; exit 1 ;;
esac
