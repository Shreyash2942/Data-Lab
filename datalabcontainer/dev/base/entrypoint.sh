#!/usr/bin/env bash
set -e

# Ensure shared runtime paths are writable by the datalab user even if the host volume was created by root.
RUNTIME_ROOT="/home/datalab/runtime"
AIRFLOW_HOME="/home/datalab/airflow"

# Create expected runtime subfolders so services don't fail on missing paths.
mkdir -p \
  "${RUNTIME_ROOT}/airflow" "${AIRFLOW_HOME}/logs" "${AIRFLOW_HOME}/pids" \
  "${RUNTIME_ROOT}/hadoop" "${RUNTIME_ROOT}/kafka" "${RUNTIME_ROOT}/spark" \
  "${RUNTIME_ROOT}/hive" "${RUNTIME_ROOT}/dbt" "${RUNTIME_ROOT}/terraform" \
  "${RUNTIME_ROOT}/lakehouse" "${RUNTIME_ROOT}/java" "${RUNTIME_ROOT}/scala" \
  "${RUNTIME_ROOT}/postgres" "${RUNTIME_ROOT}/mongodb" "${RUNTIME_ROOT}/redis" \
  "${RUNTIME_ROOT}/kafka/data" "${RUNTIME_ROOT}/kafka/logs" \
  "${RUNTIME_ROOT}/kafka/pids" "${RUNTIME_ROOT}/kafka/zookeeper-data" \
  "${RUNTIME_ROOT}/hive/logs" "${RUNTIME_ROOT}/hive/pids" \
  "${RUNTIME_ROOT}/spark/logs" "${RUNTIME_ROOT}/spark/pids" \
  "${RUNTIME_ROOT}/spark/events" "${RUNTIME_ROOT}/spark/warehouse" \
  "${RUNTIME_ROOT}/airflow/logs" "${RUNTIME_ROOT}/airflow/pids"

# Fix ownership for the shared mounts and Airflow home.
chown -R datalab:datalab "${RUNTIME_ROOT}" "${AIRFLOW_HOME}" 2>/dev/null || true

# Normalize CRLF for host-mounted scripts (Windows checkouts) to avoid
# `/usr/bin/env: 'bash\r': No such file or directory` at runtime.
if [ -d "/home/datalab/app" ]; then
  find /home/datalab/app -type f \( -name "*.sh" -o -name "start" -o -name "stop" -o -name "restart" -o -name "ui_services" -o -name "datalab-check" -o -name "hive" -o -name "hivecli" -o -name "hivelegacy" -o -name "spark-submit" -o -name "spark-sql" \) \
    -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
  find /home/datalab/app/bin -type f -exec chmod +x {} \; 2>/dev/null || true
  find /home/datalab/app/scripts -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
fi

exec "$@"
