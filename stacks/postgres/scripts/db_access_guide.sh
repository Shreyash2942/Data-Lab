#!/usr/bin/env bash
set -euo pipefail

# Prints DB + IDE connection values using dynamic host-port mapping.
# Intended to run inside the Data Lab container from ~/postgres/scripts/.

UI_HOST="${DATALAB_UI_HOST:-localhost}"
UI_MAP_FILE="${UI_MAP_FILE:-/home/datalab/runtime/ui-port-map.env}"
HOST_PORT_MAP="${DATALAB_HOST_PORT_MAP:-}"

load_ui_map() {
  [[ -n "${HOST_PORT_MAP}" ]] && return 0
  [[ -f "${UI_MAP_FILE}" ]] || return 0
  while IFS='=' read -r key value; do
    case "${key}" in
      DATALAB_UI_HOST) [[ -n "${value}" ]] && UI_HOST="${value}" ;;
      DATALAB_HOST_PORT_MAP) [[ -n "${value}" ]] && HOST_PORT_MAP="${value}" ;;
    esac
  done < "${UI_MAP_FILE}"
}

mapped_port() {
  local container_port="${1}"
  load_ui_map
  if [[ -n "${HOST_PORT_MAP}" ]]; then
    local entry cport hport
    IFS=',' read -ra entries <<< "${HOST_PORT_MAP}"
    for entry in "${entries[@]}"; do
      cport="${entry%%=*}"
      hport="${entry#*=}"
      if [[ "${cport}" == "${container_port}" ]] && [[ "${hport}" =~ ^[0-9]+$ ]]; then
        printf '%s' "${hport}"
        return 0
      fi
    done
  fi
  printf '%s' "${container_port}"
}

prompt_default() {
  local label="${1}"
  local def="${2}"
  local val
  read -r -p "${label} [${def}]: " val || true
  if [[ -z "${val}" ]]; then
    printf '%s' "${def}"
  else
    printf '%s' "${val}"
  fi
}

pg_port="$(mapped_port 5432)"
mongo_port="$(mapped_port 27017)"
redis_port="$(mapped_port 6379)"
minio_api_port="$(mapped_port 9004)"
minio_console_port="$(mapped_port 9005)"

echo "=== Data Lab Access Guide ==="
echo "This guide shows host-side URLs and tool connection values."
echo ""

pg_user="$(prompt_default "PostgreSQL username" "admin")"
pg_pass="$(prompt_default "PostgreSQL password" "admin")"
mongo_user="$(prompt_default "MongoDB username" "admin")"
mongo_pass="$(prompt_default "MongoDB password" "admin")"
redis_pass="$(prompt_default "Redis password (blank if none)" "")"
minio_user="$(prompt_default "MinIO access key" "minio_admin")"
minio_pass="$(prompt_default "MinIO secret key" "minioadmin")"
minio_region="$(prompt_default "MinIO region" "us-east-1")"
minio_bucket="$(prompt_default "MinIO bucket example" "datalab")"

echo ""
echo "=== Browser UIs (host machine) ==="
echo "pgAdmin (if started):  http://${UI_HOST}:8181/"
echo "MinIO Console:         http://${UI_HOST}:${minio_console_port}/"
echo ""

echo "=== PostgreSQL (VS Code / pgAdmin / PyCharm) ==="
echo "Host:      ${UI_HOST}"
echo "Port:      ${pg_port}"
echo "Database:  postgres (or datalab)"
echo "Username:  ${pg_user}"
echo "Password:  ${pg_pass}"
echo "SSL Mode:  prefer (or disable)"
echo ""

echo "=== MongoDB (Compass / VS Code MongoDB extension) ==="
echo "Host:      ${UI_HOST}"
echo "Port:      ${mongo_port}"
echo "Auth DB:   admin"
echo "Username:  ${mongo_user}"
echo "Password:  ${mongo_pass}"
echo "URI:       mongodb://${mongo_user}:${mongo_pass}@${UI_HOST}:${mongo_port}/admin?authSource=admin"
echo ""

echo "=== Redis (Redis Insight / redis-cli) ==="
echo "Host:      ${UI_HOST}"
echo "Port:      ${redis_port}"
if [[ -n "${redis_pass}" ]]; then
  echo "Password:  ${redis_pass}"
  echo "URI:       redis://:${redis_pass}@${UI_HOST}:${redis_port}"
else
  echo "Password:  (none)"
  echo "URI:       redis://${UI_HOST}:${redis_port}"
fi
echo ""
echo "=== MinIO (S3 API / SDKs / CLI) ==="
echo "Endpoint:   http://${UI_HOST}:${minio_api_port}"
echo "Console:    http://${UI_HOST}:${minio_console_port}/"
echo "Access Key: ${minio_user}"
echo "Secret Key: ${minio_pass}"
echo "Region:     ${minio_region}"
echo "Bucket URI: s3://${minio_bucket}/"
echo "Path Style: true"
echo "AWS env:    AWS_ACCESS_KEY_ID=${minio_user}"
echo "            AWS_SECRET_ACCESS_KEY=${minio_pass}"
echo "            AWS_DEFAULT_REGION=${minio_region}"
echo "            AWS_ENDPOINT_URL=http://${UI_HOST}:${minio_api_port}"
echo "AWS CLI:    aws --endpoint-url http://${UI_HOST}:${minio_api_port} s3 ls"
echo "Bucket cmd: aws --endpoint-url http://${UI_HOST}:${minio_api_port} s3 mb s3://${minio_bucket}"
echo ""
echo "Tip: Run this again any time after container/port changes."
