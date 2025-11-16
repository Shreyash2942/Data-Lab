#!/usr/bin/env bash
set -e

SERVICE_NAME="data-lab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_SCRIPT_PATH="/home/datalab/app/services_start.sh"
LOCAL_START_SCRIPT="${SCRIPT_DIR}/services_start.sh"

if command -v docker >/dev/null 2>&1; then
  run_in_container() {
    docker compose exec "${SERVICE_NAME}" bash -lc "${START_SCRIPT_PATH} $1"
  }
  can_restart_container=true
else
  run_in_container() {
    bash "${LOCAL_START_SCRIPT}" "$1"
  }
  can_restart_container=false
fi

restart_pair() {
  run_in_container "$1"
  run_in_container "$2"
}

echo "=== Data Lab :: RESTART MENU ==="
echo "1) Restart Spark services"
echo "2) Restart Hadoop services"
echo "3) Restart Hive services"
echo "4) Restart Kafka services"
echo "5) Restart Airflow webserver & scheduler"
echo "6) Restart ALL core services (Spark/Hadoop/Hive/Kafka)"
echo "7) Restart Docker container only"
echo "0) Exit"
read -p "Select option: " opt

case "$opt" in
  1)
    restart_pair --stop-spark --start-spark
    echo "[+] Spark services restarted."
    ;;
  2)
    restart_pair --stop-hadoop --start-hadoop
    echo "[+] Hadoop services restarted."
    ;;
  3)
    restart_pair --stop-hive --start-hive
    echo "[+] Hive services restarted."
    ;;
  4)
    restart_pair --stop-kafka --start-kafka
    echo "[+] Kafka services restarted."
    ;;
  5)
    restart_pair --stop-airflow --start-airflow
    echo "[+] Airflow services restarted."
    ;;
  6)
    run_in_container --restart-core
    echo "[+] Spark/Hadoop/Hive/Kafka services restarted."
    ;;
  7)
    if [ "${can_restart_container}" = true ]; then
      docker compose restart "${SERVICE_NAME}"
    else
      echo "Docker CLI not available in this shell; run this option from the host."
      exit 1
    fi
    ;;
  0)
    echo "Bye."
    ;;
  *)
    echo "Invalid option."
    exit 1
    ;;
esac
