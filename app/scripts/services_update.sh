#!/usr/bin/env bash
set -e

SERVICE_NAME="data-lab"

echo "=== Data Lab :: UPDATE (Rebuild Image) ==="
echo "1) Rebuild image only"
echo "2) Rebuild, restart container, and start Spark/Hadoop/Hive/Kafka services"
echo "3) Rebuild, restart container, start services, and run all tech stack demos"
echo "0) Exit"
read -p "Select option: " opt

case "$opt" in
  1)
    docker compose build
    ;;
  2)
    docker compose build
    docker compose up -d
    echo "[*] Starting core services inside container..."
    docker compose exec ${SERVICE_NAME} bash -lc "/workspace/app/scripts/services_start.sh --start-core"
    echo "✅ Container refreshed and Spark/Hadoop/Hive/Kafka services started."
    ;;
  3)
    docker compose build
    docker compose up -d
    echo "[*] Starting core services inside container..."
    docker compose exec ${SERVICE_NAME} bash -lc "/workspace/app/scripts/services_start.sh --start-core"
    echo "[*] Running tech stack demos..."
    docker compose exec ${SERVICE_NAME} bash -lc "/workspace/app/scripts/services_start.sh --run-all-demos"
    echo "✅ Container refreshed, services started, and all tech stack demos executed."
    ;;
  0)
    echo "Bye."
    ;;
  *)
    echo "Invalid option."
    exit 1
    ;;
esac
