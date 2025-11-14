#!/usr/bin/env bash
set -e

SERVICE_NAME="data-lab"

run_in_container() {
  docker compose exec "${SERVICE_NAME}" bash -lc "/home/datalab/app/services_start.sh $1"
}

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
    ;;
  2)
    restart_pair --stop-hadoop --start-hadoop
    ;;
  3)
    restart_pair --stop-hive --start-hive
    ;;
  4)
    restart_pair --stop-kafka --start-kafka
    ;;
  5)
    restart_pair --stop-airflow --start-airflow
    ;;
  6)
    run_in_container --restart-core
    ;;
  7)
    docker compose restart "${SERVICE_NAME}"
    ;;
  0)
    echo "Bye."
    ;;
  *)
    echo "Invalid option."
    exit 1
    ;;
esac
