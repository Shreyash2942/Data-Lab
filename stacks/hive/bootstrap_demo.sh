#!/usr/bin/env bash
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run with bash." >&2
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
: "${HADOOP_HOME:=/opt/hadoop}"
: "${HIVE_CLI_HOST:=localhost}"
: "${HIVE_CLI_PORT:=10001}"
: "${HIVE_CLI_HTTP_PATH:=cliservice}"
: "${HIVE_CLI_AUTH:=noSasl}"
: "${HIVE_CLI_DB:=default}"
: "${HIVE_CLI_USER:=datalab}"
: "${HIVE_CLI_PASS:=}"
HIVE_HOME="$(strip_cr "${HIVE_HOME}")"
HADOOP_HOME="$(strip_cr "${HADOOP_HOME}")"
HIVE_CLI_HOST="$(strip_cr "${HIVE_CLI_HOST}")"
HIVE_CLI_PORT="$(strip_cr "${HIVE_CLI_PORT}")"
HIVE_CLI_HTTP_PATH="$(strip_cr "${HIVE_CLI_HTTP_PATH}")"
HIVE_CLI_AUTH="$(strip_cr "${HIVE_CLI_AUTH}")"
HIVE_CLI_DB="$(strip_cr "${HIVE_CLI_DB}")"
HIVE_CLI_USER="$(strip_cr "${HIVE_CLI_USER}")"
HIVE_CLI_PASS="$(strip_cr "${HIVE_CLI_PASS}")"
HIVE_BIN="${HIVE_HOME}/bin/hive"
BEELINE_BIN="${HIVE_HOME}/bin/beeline"
CONNECT_HOST="${HIVE_CLI_HOST}"
# 0.0.0.0 is not connectable; use loopback instead.
if [ "${CONNECT_HOST}" = "0.0.0.0" ]; then
  CONNECT_HOST="127.0.0.1"
fi
JDBC_URL="jdbc:hive2://${CONNECT_HOST}:${HIVE_CLI_PORT}/${HIVE_CLI_DB};transportMode=http;httpPath=${HIVE_CLI_HTTP_PATH};auth=${HIVE_CLI_AUTH}"

if [ ! -x "${BEELINE_BIN}" ]; then
  echo "Beeline not found at ${BEELINE_BIN}" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_SQL="${SCRIPT_DIR}/init_demo_databases.sql"
CLI_WRAPPER="${WORKSPACE}/app/scripts/hive/cli.sh"

if [ ! -f "${INIT_SQL}" ]; then
  echo "Missing init SQL at ${INIT_SQL}" >&2
  exit 1
fi

wait_port() {
  local host="$1" port="$2" retries="${3:-300}"
  for _ in $(seq 1 $retries); do
    if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

echo "[*] Waiting for HiveServer2 on ${CONNECT_HOST}:${HIVE_CLI_PORT} (up to 300s)..."
if ! wait_port "${CONNECT_HOST}" "${HIVE_CLI_PORT}" 300; then
  echo "HiveServer2 not reachable on ${CONNECT_HOST}:${HIVE_CLI_PORT} after waiting" >&2
  exit 1
fi

echo "[*] Initializing demo databases via Beeline..."
if [ -x "${CLI_WRAPPER}" ]; then
  HIVE_CLI_SKIP_RC=1 \
  HIVE_CLI_HOST="${CONNECT_HOST}" \
  HIVE_CLI_PORT="${HIVE_CLI_PORT}" \
  HIVE_CLI_HTTP_PATH="${HIVE_CLI_HTTP_PATH}" \
  HIVE_CLI_AUTH="${HIVE_CLI_AUTH}" \
  HIVE_CLI_DB="${HIVE_CLI_DB}" \
  HIVE_CLI_USER="${HIVE_CLI_USER}" \
  HIVE_CLI_PASS="${HIVE_CLI_PASS}" \
    bash "${CLI_WRAPPER}" -f "${INIT_SQL}"
else
  "${BEELINE_BIN}" --silent=true --verbose=false \
    -u "${JDBC_URL}" -n "${HIVE_CLI_USER}" -p "${HIVE_CLI_PASS}" -f "${INIT_SQL}"
fi
echo "[+] Hive demo databases initialized."
