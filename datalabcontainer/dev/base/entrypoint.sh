#!/usr/bin/env bash
set -e

# Ensure shared runtime paths are writable by the datalab user even if the host volume was created by root.
RUNTIME_ROOT="/home/datalab/runtime"
AIRFLOW_HOME="${RUNTIME_ROOT}/airflow"
RUNTIME_CONFIG_DIR="${RUNTIME_ROOT}/config"
RUNTIME_OVERRIDE_FILE="${RUNTIME_CONFIG_DIR}/datalab-overrides.env"
RUNTIME_BOOTSTRAP_SENTINEL="${RUNTIME_CONFIG_DIR}/.datalab-bootstrap-initialized"

# Create expected runtime subfolders so services don't fail on missing paths.
runtime_paths=(
  "${AIRFLOW_HOME}/logs"
  "${AIRFLOW_HOME}/pids"
  "${RUNTIME_ROOT}/hadoop"
  "${RUNTIME_ROOT}/kafka"
  "${RUNTIME_ROOT}/spark"
  "${RUNTIME_ROOT}/hive"
  "${RUNTIME_ROOT}/dbt"
  "${RUNTIME_ROOT}/terraform"
  "${RUNTIME_ROOT}/lakehouse"
  "${RUNTIME_ROOT}/java"
  "${RUNTIME_ROOT}/scala"
  "${RUNTIME_ROOT}/postgres"
  "${RUNTIME_ROOT}/mongodb"
  "${RUNTIME_ROOT}/redis"
  "${RUNTIME_ROOT}/kafka/data"
  "${RUNTIME_ROOT}/kafka/logs"
  "${RUNTIME_ROOT}/kafka/pids"
  "${RUNTIME_ROOT}/kafka/zookeeper-data"
  "${RUNTIME_ROOT}/hive/logs"
  "${RUNTIME_ROOT}/hive/pids"
  "${RUNTIME_ROOT}/spark/logs"
  "${RUNTIME_ROOT}/spark/pids"
  "${RUNTIME_ROOT}/spark/events"
  "${RUNTIME_ROOT}/spark/warehouse"
  "${RUNTIME_ROOT}/airflow/logs"
  "${RUNTIME_ROOT}/airflow/pids"
  "${RUNTIME_CONFIG_DIR}"
)
mkdir -p "${runtime_paths[@]}"

# Fix ownership for the shared mounts and Airflow home.
chown -R datalab:datalab "${RUNTIME_ROOT}" "${AIRFLOW_HOME}" 2>/dev/null || true

# Normalize CRLF for host-mounted scripts (Windows checkouts) to avoid
# `/usr/bin/env: 'bash\r': No such file or directory` at runtime.
if [ -d "/home/datalab/app" ]; then
  find /home/datalab/app -type f \( -name "*.sh" -o -name "start" -o -name "stop" -o -name "restart" -o -name "ui_services" -o -name "datalab-check" -o -name "hive" -o -name "hivecli" -o -name "hivelegacy" -o -name "spark-submit" -o -name "spark-sql" \) \
    -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
  find /home/datalab/app/bin -type f -exec chmod +x {} \; 2>/dev/null || true
  find /home/datalab/app/tech -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
  find /home/datalab/app/scripts -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
fi

if [ -d "/home/datalab/datalabconfig" ]; then
  find /home/datalab/datalabconfig -type f -name "*.sh" -exec sed -i 's/\r$//' {} \; 2>/dev/null || true
  find /home/datalab/datalabconfig -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
fi

bootstrap_runtime_defaults() {
  if [ -f "${RUNTIME_BOOTSTRAP_SENTINEL}" ] || [ -f "${RUNTIME_OVERRIDE_FILE}" ]; then
    return 0
  fi

  if [ ! -f "/home/datalab/datalabconfig/lib/recommend.sh" ] || [ ! -f "/home/datalab/datalabconfig/lib/common.sh" ] || [ ! -f "/home/datalab/datalabconfig/lib/detect.sh" ] || [ ! -f "/home/datalab/app/tech/common.sh" ]; then
    return 0
  fi

  mkdir -p "${RUNTIME_CONFIG_DIR}"
  if bash -lc '
set -euo pipefail
source /home/datalab/app/tech/common.sh
source /home/datalab/datalabconfig/lib/common.sh
source /home/datalab/datalabconfig/lib/detect.sh
source /home/datalab/datalabconfig/lib/recommend.sh
config::prepare_bootstrap_defaults
cat > "'"${RUNTIME_OVERRIDE_FILE}"'" <<EOF
# Data Lab runtime overrides
# Generated automatically on first container start
# Baseline bootstrap uses about 20% of effective CPU for compute services
$(config::recommended_env_lines)
EOF
' >/dev/null 2>&1; then
    touch "${RUNTIME_BOOTSTRAP_SENTINEL}"
    chown datalab:datalab "${RUNTIME_OVERRIDE_FILE}" "${RUNTIME_BOOTSTRAP_SENTINEL}" 2>/dev/null || true
  fi
}

bootstrap_runtime_defaults

exec "$@"
