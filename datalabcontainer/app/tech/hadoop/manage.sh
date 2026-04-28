#!/usr/bin/env bash
# shellcheck disable=SC1091

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

HADOOP_NAMENODE_PATTERN='org\.apache\.hadoop\.hdfs\.server\.namenode\.NameNode'
HADOOP_DATANODE_PATTERN='org\.apache\.hadoop\.hdfs\.server\.datanode\.DataNode'
HADOOP_RESOURCEMANAGER_PATTERN='org\.apache\.hadoop\.yarn\.server\.resourcemanager\.ResourceManager'
HADOOP_NODEMANAGER_PATTERN='org\.apache\.hadoop\.yarn\.server\.nodemanager\.NodeManager'
HADOOP_HISTORYSERVER_PATTERN='org\.apache\.hadoop\.mapreduce\.v2\.hs\.JobHistoryServer'

hadoop::daemon_running() {
  pgrep -f "$1" >/dev/null 2>&1
}

hadoop::all_daemons_running() {
  local pattern
  for pattern in "$@"; do
    if ! hadoop::daemon_running "${pattern}"; then
      return 1
    fi
  done
  return 0
}

hadoop::is_running() {
  hadoop::all_daemons_running \
    "${HADOOP_NAMENODE_PATTERN}" \
    "${HADOOP_DATANODE_PATTERN}" \
    "${HADOOP_RESOURCEMANAGER_PATTERN}" \
    "${HADOOP_NODEMANAGER_PATTERN}"
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

hadoop::ensure_mapreduce_config() {
  local mapred_site="${HADOOP_HOME}/etc/hadoop/mapred-site.xml"
  cat >"${mapred_site}" <<EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <property>
    <name>mapreduce.framework.name</name>
    <value>yarn</value>
  </property>
  <property>
    <name>mapreduce.jobhistory.address</name>
    <value>0.0.0.0:10020</value>
  </property>
  <property>
    <name>mapreduce.jobhistory.webapp.address</name>
    <value>0.0.0.0:19888</value>
  </property>
  <property>
    <name>mapreduce.application.classpath</name>
    <value>${HADOOP_MAPRED_HOME}/share/hadoop/mapreduce/*:${HADOOP_MAPRED_HOME}/share/hadoop/mapreduce/lib/*</value>
  </property>
  <property>
    <name>yarn.app.mapreduce.am.env</name>
    <value>HADOOP_MAPRED_HOME=${HADOOP_MAPRED_HOME}</value>
  </property>
  <property>
    <name>mapreduce.map.env</name>
    <value>HADOOP_MAPRED_HOME=${HADOOP_MAPRED_HOME}</value>
  </property>
  <property>
    <name>mapreduce.reduce.env</name>
    <value>HADOOP_MAPRED_HOME=${HADOOP_MAPRED_HOME}</value>
  </property>
</configuration>
EOF
}

hadoop::ensure_yarn_config() {
  local yarn_site="${HADOOP_HOME}/etc/hadoop/yarn-site.xml"
  local rm_host="${YARN_RM_HOST:-0.0.0.0}"
  local nm_host="${YARN_NM_HOST:-0.0.0.0}"
  cat >"${yarn_site}" <<EOF
<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <property>
    <name>yarn.nodemanager.aux-services</name>
    <value>mapreduce_shuffle</value>
  </property>
  <property>
    <name>yarn.nodemanager.aux-services.mapreduce.shuffle.class</name>
    <value>org.apache.hadoop.mapred.ShuffleHandler</value>
  </property>
  <property>
    <name>yarn.resourcemanager.hostname</name>
    <value>${rm_host}</value>
  </property>
  <property>
    <name>yarn.resourcemanager.address</name>
    <value>${rm_host}:8032</value>
  </property>
  <property>
    <name>yarn.resourcemanager.scheduler.address</name>
    <value>${rm_host}:8030</value>
  </property>
  <property>
    <name>yarn.resourcemanager.resource-tracker.address</name>
    <value>${rm_host}:8031</value>
  </property>
  <property>
    <name>yarn.resourcemanager.webapp.address</name>
    <value>${rm_host}:8088</value>
  </property>
  <property>
    <name>yarn.nodemanager.webapp.address</name>
    <value>${nm_host}:8042</value>
  </property>
  <property>
    <name>yarn.resourcemanager.bind-host</name>
    <value>0.0.0.0</value>
  </property>
  <property>
    <name>yarn.resourcemanager.webapp.bind-host</name>
    <value>0.0.0.0</value>
  </property>
  <property>
    <name>yarn.nodemanager.bind-host</name>
    <value>0.0.0.0</value>
  </property>
  <property>
    <name>yarn.nodemanager.webapp.bind-host</name>
    <value>0.0.0.0</value>
  </property>
</configuration>
EOF
}

hadoop::format_namenode_if_needed() {
  if [ ! -f "${HDFS_NAME_DIR}/current/VERSION" ]; then
    echo "[*] Formatting NameNode (first-run)..."
    "${HDFS_BIN}" namenode -format -force -nonInteractive
  fi
}

hadoop::pid_file_for_daemon() {
  local daemon="$1"
  local pid_dir="${HADOOP_PID_DIR:-/tmp}"
  printf '%s/hadoop-%s-%s.pid' "${pid_dir}" "$(id -un)" "${daemon}"
}

hadoop::cleanup_stale_daemon_pid() {
  local daemon="$1"
  local pid_file pid
  pid_file="$(hadoop::pid_file_for_daemon "${daemon}")"
  [[ -f "${pid_file}" ]] || return 0
  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  if [[ ! "${pid}" =~ ^[0-9]+$ ]] || ! kill -0 "${pid}" 2>/dev/null; then
    rm -f "${pid_file}"
  fi
}

hadoop::start_hdfs_daemon() {
  local label="$1"
  local pattern="$2"
  local daemon="$3"
  if hadoop::daemon_running "${pattern}"; then
    echo "[*] Hadoop ${label} already running."
    return 0
  fi
  hadoop::cleanup_stale_daemon_pid "${daemon}"
  "${HDFS_BIN}" --daemon start "${daemon}"
}

hadoop::start_yarn_daemon() {
  local label="$1"
  local pattern="$2"
  local daemon="$3"
  if hadoop::daemon_running "${pattern}"; then
    echo "[*] Hadoop ${label} already running."
    return 0
  fi
  hadoop::cleanup_stale_daemon_pid "${daemon}"
  env -u YARN_LOG_DIR "${YARN_BIN}" --daemon start "${daemon}"
}

hadoop::start_mapred_daemon() {
  local label="$1"
  local pattern="$2"
  local daemon="$3"
  if hadoop::daemon_running "${pattern}"; then
    echo "[*] Hadoop ${label} already running."
    return 0
  fi
  hadoop::cleanup_stale_daemon_pid "${daemon}"
  env -u YARN_LOG_DIR "${MAPRED_BIN}" --daemon start "${daemon}" || true
}

hadoop::start() {
  hadoop::ensure_dirs
  hadoop::ensure_mapreduce_config
  hadoop::ensure_yarn_config
  hadoop::format_namenode_if_needed
  echo "[*] Starting Hadoop daemons..."
  hadoop::start_hdfs_daemon "NameNode" "${HADOOP_NAMENODE_PATTERN}" namenode
  hadoop::start_hdfs_daemon "DataNode" "${HADOOP_DATANODE_PATTERN}" datanode
  hadoop::start_yarn_daemon "ResourceManager" "${HADOOP_RESOURCEMANAGER_PATTERN}" resourcemanager
  hadoop::start_yarn_daemon "NodeManager" "${HADOOP_NODEMANAGER_PATTERN}" nodemanager
  hadoop::start_mapred_daemon "JobHistoryServer" "${HADOOP_HISTORYSERVER_PATTERN}" historyserver
  jps
  echo "HDFS UI: $(common::ui_url 9870 "/")  |  YARN UI: $(common::ui_url 8088 "/")"
}

hadoop::patterns_running() {
  local pattern
  for pattern in "$@"; do
    if pgrep -f "${pattern}" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

hadoop::signal_patterns() {
  local signal="$1"
  shift
  local pattern
  for pattern in "$@"; do
    if pgrep -f "${pattern}" >/dev/null 2>&1; then
      pkill "-${signal}" -f "${pattern}" >/dev/null 2>&1 || true
    fi
  done
}

hadoop::wait_patterns_exit() {
  local timeout="$1"
  shift
  local deadline
  deadline=$((SECONDS + timeout))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if ! hadoop::patterns_running "$@"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

hadoop::stop() {
  local -a daemon_patterns=(
    "${HADOOP_HISTORYSERVER_PATTERN}"
    "${HADOOP_NODEMANAGER_PATTERN}"
    "${HADOOP_RESOURCEMANAGER_PATTERN}"
    "${HADOOP_DATANODE_PATTERN}"
    "${HADOOP_NAMENODE_PATTERN}"
  )

  echo "[*] Stopping Hadoop daemons..."
  env -u YARN_LOG_DIR "${MAPRED_BIN}" --daemon stop historyserver >/dev/null 2>&1 || true
  env -u YARN_LOG_DIR "${YARN_BIN}" --daemon stop nodemanager >/dev/null 2>&1 || true
  env -u YARN_LOG_DIR "${YARN_BIN}" --daemon stop resourcemanager >/dev/null 2>&1 || true
  "${HDFS_BIN}" --daemon stop datanode >/dev/null 2>&1 || true
  "${HDFS_BIN}" --daemon stop namenode >/dev/null 2>&1 || true

  # Ensure leftover daemon JVMs are terminated without sequential per-process waits.
  hadoop::signal_patterns TERM "${daemon_patterns[@]}"
  if ! hadoop::wait_patterns_exit 8 "${daemon_patterns[@]}"; then
    echo "[*] Forcing remaining Hadoop daemons to stop..."
    hadoop::signal_patterns KILL "${daemon_patterns[@]}"
    hadoop::wait_patterns_exit 3 "${daemon_patterns[@]}" || true
  fi
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
