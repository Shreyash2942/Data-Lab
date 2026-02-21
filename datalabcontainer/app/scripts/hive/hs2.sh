#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APP_REPO_ROOT="$(cd "${APP_DIR}/.." && pwd)"
SERVICE_NAME="${SERVICE_NAME:-data-lab}"
CONTAINER_NAME="${CONTAINER_NAME:-datalab}"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_PATH_FROM_APP="scripts/hive/${SCRIPT_NAME}"
source "${APP_DIR}/scripts/host_exec.sh"

datalab::ensure_inside_or_exec "${APP_REPO_ROOT}" "${SERVICE_NAME}" "${CONTAINER_NAME}" "/home/datalab/app/${SCRIPT_PATH_FROM_APP}" "$@"

source "${APP_DIR}/scripts/common.sh"
source "${APP_DIR}/scripts/hadoop/manage.sh"
source "${APP_DIR}/scripts/hive/manage.sh"

command=${1:-start}

case "${command}" in
  start)
    hadoop::ensure_running
    hive::ensure_dirs
    hive::init_metastore_if_needed
    hive::start_hs2
    hive::verify_query
    ;;
  stop)
    hive::stop
    ;;
  restart)
    hive::stop || true
    hadoop::ensure_running
    hive::ensure_dirs
    hive::init_metastore_if_needed
    hive::start_hs2
    hive::verify_query
    ;;
  status)
    if hive::hs2_running; then
      if [[ -f "${HIVE_HS2_HTTP_PID_FILE}" ]]; then
        echo "[+] HiveServer2 running (PID $(cat "${HIVE_HS2_HTTP_PID_FILE}"))"
      else
        echo "[+] HiveServer2 running."
      fi
    else
      echo "[-] HiveServer2 not running."
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}" >&2
    exit 1
    ;;
esac
