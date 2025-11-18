#!/usr/bin/env bash
# shellcheck disable=SC1091

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

hadoop::is_running() {
  pgrep -f NameNode >/dev/null 2>&1 && pgrep -f ResourceManager >/dev/null 2>&1
}

hadoop::ensure_dirs() {
  mkdir -p \
    "${HDFS_NAME_DIR}" \
    "${HDFS_DATA_DIR}" \
    "${RUNTIME_ROOT}/hadoop/tmp" \
    "${HADOOP_LOG_DIR}" \
    "${YARN_LOG_DIR}" \
    "${MAPRED_LOG_DIR}"
}

hadoop::format_namenode_if_needed() {
  if [ ! -f "${HDFS_NAME_DIR}/current/VERSION" ]; then
    echo "[*] Formatting NameNode (first-run)..."
    "${HDFS_BIN}" namenode -format -force -nonInteractive
  fi
}

hadoop::start() {
  hadoop::ensure_dirs
  hadoop::format_namenode_if_needed
  echo "[*] Starting Hadoop daemons..."
  "${HDFS_BIN}" --daemon start namenode
  "${HDFS_BIN}" --daemon start datanode
  "${YARN_BIN}" --daemon start resourcemanager
  "${YARN_BIN}" --daemon start nodemanager
  "${MAPRED_BIN}" --daemon start historyserver || true
  jps
  echo "HDFS UI: http://localhost:9870  |  YARN UI: http://localhost:8088"
}

hadoop::stop() {
  echo "[*] Stopping Hadoop daemons..."
  "${MAPRED_BIN}" --daemon stop historyserver || true
  "${YARN_BIN}" --daemon stop nodemanager || true
  "${YARN_BIN}" --daemon stop resourcemanager || true
  "${HDFS_BIN}" --daemon stop datanode || true
  "${HDFS_BIN}" --daemon stop namenode || true
}

hadoop::ensure_running() {
  if hadoop::is_running; then
    echo "[*] Hadoop already running."
    return
  fi
  echo "[*] Hadoop not running; starting now..."
  hadoop::start
  echo "[*] Waiting for Hadoop services to stabilize..."
  sleep 5
}
