#!/usr/bin/env bash
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash (try: bash bootstrap_demo.sh)." >&2
  exit 1
fi

strip_cr() {
  local value="${1:-}"
  value="${value//$'\r'/}"
  printf '%s' "${value}"
}

HOME_DIR="$(strip_cr "${HOME:-/home/datalab}")"
WORKSPACE="$(strip_cr "${WORKSPACE:-${HOME_DIR}}")"
: "${HIVE_HOME:=/opt/hive}"
HIVE_HOME="$(strip_cr "${HIVE_HOME}")"
HIVE_BIN="${HIVE_HOME}/bin/hive"

SQL_FILE="${WORKSPACE}/hive/init_demo_databases.sql"

if [ ! -x "${HIVE_BIN}" ]; then
  echo "Cannot find Hive CLI at ${HIVE_BIN}. Is Hive installed?" >&2
  exit 1
fi

if [ ! -f "${SQL_FILE}" ]; then
  echo "Expected SQL file ${SQL_FILE} not found." >&2
  exit 1
fi

HIVE_ARGS=(--hiveconf hive.cli.print.current.db=true)

run_hive() {
  "${HIVE_BIN}" "${HIVE_ARGS[@]}" "$@"
}

echo "[*] Using Hive CLI (${HIVE_BIN}) with current-db prompt enabled..."
echo "[*] Creating demo databases/tables from ${SQL_FILE}..."
run_hive -f "${SQL_FILE}"

echo "[*] Listing databases..."
run_hive -e "SHOW DATABASES;"

echo "[*] Previewing demo tables..."
run_hive -e "SELECT * FROM sales_demo.daily_orders;"
run_hive -e "SELECT * FROM analytics_demo.customer_metrics;"
run_hive -e "SELECT * FROM staging_demo.raw_events;"

echo "[+] Hive demo databases ready."
