#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="data-lab"

echo "=== Data Lab :: RESTART MENU ==="
echo "1) Restart ALL tech stack services (Spark/Hadoop/Hive/Kafka)"
echo "2) Restart Docker container then start all tech stack services"
echo "0) Exit"
read -p "Select option: " opt

case "$opt" in
  1)
    bash "${SCRIPT_DIR}/services_start.sh" --restart-core
    echo "Core Spark/Hadoop/Hive/Kafka services restarted."
    ;;
  2)
    docker compose restart ${SERVICE_NAME} || true
    bash "${SCRIPT_DIR}/services_start.sh" --start-core
    echo "Container and core services restarted."
    ;;
  0)
    echo "Bye."
    ;;
  *)
    echo "Invalid option."
    exit 1
    ;;
esac
