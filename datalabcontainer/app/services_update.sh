#!/usr/bin/env bash
set -e

SERVICE_NAME="data-lab"

exec_in_container() {
  docker compose exec "${SERVICE_NAME}" bash -lc "$1"
}

launch_start_menu() {
  echo "[*] Opening service start menu inside the container..."
  exec_in_container "/home/datalab/app/services_start.sh" || true
}

launch_demo_menu() {
  echo "[*] Opening demo menu inside the container..."
  exec_in_container "/home/datalab/app/services_demo.sh" || true
}

rebuild_and_maybe_restart() {
  docker compose build
  case "$1" in
    restart)
      docker compose up -d --force-recreate
      read -p "Launch the service start menu now? [y/N]: " start_ans
      if [[ "${start_ans}" =~ ^[Yy]$ ]]; then
        launch_start_menu
      fi
      read -p "Launch the demo menu as well? [y/N]: " demo_ans
      if [[ "${demo_ans}" =~ ^[Yy]$ ]]; then
        launch_demo_menu
      fi
      echo "Update workflow complete."
      ;;
  esac
}

echo "=== Data Lab :: UPDATE (Rebuild Image) ==="
echo "1) Rebuild image only"
echo "2) Rebuild, recreate container, then optionally launch menus"
echo "0) Exit"
read -p "Select option: " opt

case "${opt}" in
  1)
    rebuild_and_maybe_restart only
    ;;
  2)
    rebuild_and_maybe_restart restart
    ;;
  0)
    echo "Bye."
    ;;
  *)
    echo "Invalid option."
    exit 1
    ;;
esac
