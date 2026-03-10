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

hadoop::start() {
  hadoop::ensure_dirs
  hadoop::ensure_mapreduce_config
  hadoop::ensure_yarn_config
  hadoop::format_namenode_if_needed
  echo "[*] Starting Hadoop daemons..."
  "${HDFS_BIN}" --daemon start namenode
  "${HDFS_BIN}" --daemon start datanode
  "${YARN_BIN}" --daemon start resourcemanager
  "${YARN_BIN}" --daemon start nodemanager
  "${MAPRED_BIN}" --daemon start historyserver || true
  jps
  echo "HDFS UI: $(common::ui_url 9870 "/")  |  YARN UI: $(common::ui_url 8088 "/")"
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
