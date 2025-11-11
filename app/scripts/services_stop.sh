#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="data-lab"

echo "=== Data Lab :: STOP MENU ==="
echo "1) Stop ALL tech stack services (Spark/Hadoop/Hive/Kafka)"
echo "2) Stop all tech stack services and stop the container"
echo "0) Exit"
read -p "Select option: " opt

case "$opt" in
  1)
    bash "${SCRIPT_DIR}/services_start.sh" --stop-core
    echo "Core Spark/Hadoop/Hive/Kafka services stopped."
    ;;
  2)
    bash "${SCRIPT_DIR}/services_start.sh" --stop-core
    docker compose stop ${SERVICE_NAME} || true
    echo "Services stopped and container halted."
    ;;
  0)
    echo "Bye."
    ;;
  *)
    echo "Invalid option."
    exit 1
    ;;
esac
