#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
APP_REPO_ROOT="$(cd "${APP_DIR}/.." && pwd)"
SERVICE_NAME="${SERVICE_NAME:-data-lab}"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_PATH_FROM_APP="scripts/hive/${SCRIPT_NAME}"

if [ ! -f "/.dockerenv" ] && [ -z "${INSIDE_DATALAB:-}" ]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "Please run inside the data-lab container (docker compose exec data-lab bash)." >&2
    exit 1
  fi
  (
    cd "${APP_REPO_ROOT}"
    docker compose exec -e INSIDE_DATALAB=1 "${SERVICE_NAME}" "/home/datalab/app/${SCRIPT_PATH_FROM_APP}" "$@"
  )
  exit $?
fi

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
      echo "[+] HiveServer2 running (PID $(cat "${HIVE_HS2_PID_FILE}"))"
    else
      echo "[-] HiveServer2 not running."
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}" >&2
    exit 1
    ;;
esac
