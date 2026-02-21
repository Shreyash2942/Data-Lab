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
  "${RUNTIME_ROOT}/lakehouse"

# Fix ownership for the shared mounts and Airflow home.
chown -R datalab:datalab "${RUNTIME_ROOT}" "${AIRFLOW_HOME}" 2>/dev/null || true

exec "$@"
