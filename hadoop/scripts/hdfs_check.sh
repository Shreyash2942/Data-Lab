#!/usr/bin/env bash
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  echo "Please run this script with bash (try: bash hdfs_check.sh)." >&2
  exit 1
fi

strip_cr() {
  local value="${1:-}"
  value="${value//$'\r'/}"
  printf '%s' "${value}"
}

HOME_DIR="$(strip_cr "${HOME:-/home/datalab}")"
WORKSPACE="$(strip_cr "${WORKSPACE:-${HOME_DIR}}")"
: "${HADOOP_HOME:=/opt/hadoop}"
HADOOP_HOME="$(strip_cr "${HADOOP_HOME}")"
HDFS_BIN="${HADOOP_HOME}/bin/hdfs"

LOCAL_SAMPLE="${WORKSPACE}/hadoop/sample_data/hello_hdfs.txt"
HDFS_TARGET_DIR="/data-lab/demo"
HDFS_TARGET_FILE="${HDFS_TARGET_DIR}/hello_hdfs.txt"

if [ ! -x "${HDFS_BIN}" ]; then
  echo "Cannot find hdfs CLI at ${HDFS_BIN}. Is Hadoop installed in this container?" >&2
  exit 1
fi

if ! "${HDFS_BIN}" dfs -test -d / >/dev/null 2>&1; then
  cat >&2 <<'EOF'
HDFS is not reachable right now.
Start the Hadoop stack first via:
  bash ~/app/services_start.sh   # choose option 2 or 6
EOF
  exit 1
fi

if [ ! -f "${LOCAL_SAMPLE}" ]; then
  echo "Sample file ${LOCAL_SAMPLE} is missing." >&2
  exit 1
fi

echo "[*] Ensuring ${HDFS_TARGET_DIR} exists in HDFS..."
"${HDFS_BIN}" dfs -mkdir -p "${HDFS_TARGET_DIR}"

echo "[*] Uploading ${LOCAL_SAMPLE} to ${HDFS_TARGET_FILE}..."
"${HDFS_BIN}" dfs -put -f "${LOCAL_SAMPLE}" "${HDFS_TARGET_FILE}"

echo "[*] Listing ${HDFS_TARGET_DIR}:"
"${HDFS_BIN}" dfs -ls "${HDFS_TARGET_DIR}"

echo "[*] Preview of ${HDFS_TARGET_FILE}:"
"${HDFS_BIN}" dfs -cat "${HDFS_TARGET_FILE}"

echo "[+] HDFS smoke test complete."
