#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="data-lab"

call_control() {
  bash "${SCRIPT_DIR}/services_start.sh" "$1"
}

echo "=== Data Lab :: STOP MENU ==="
echo "1) Stop Spark services"
echo "2) Stop Hadoop services"
echo "3) Stop Hive services"
echo "4) Stop Kafka services"
echo "5) Stop Airflow webserver & scheduler"
echo "6) Stop ALL core services (Spark/Hadoop/Hive/Kafka)"
echo "7) Stop Docker container"
echo "0) Exit"
read -p "Select option: " opt

case "$opt" in
  1)
    call_control --stop-spark
    echo "[+] Spark services stopped."
    ;;
  2)
    call_control --stop-hadoop
    echo "[+] Hadoop services stopped."
    ;;
  3)
    call_control --stop-hive
    echo "[+] Hive services stopped."
    ;;
  4)
    call_control --stop-kafka
    echo "[+] Kafka services stopped."
    ;;
  5)
    call_control --stop-airflow
    echo "[+] Airflow services stopped."
    ;;
  6)
    call_control --stop-core
    echo "[+] Spark/Hadoop/Hive/Kafka services stopped."
    ;;
  7)
    docker compose stop "${SERVICE_NAME}"
    ;;
  0)
    echo "Bye."
    ;;
  *)
    echo "Invalid option."
    exit 1
    ;;
esac
