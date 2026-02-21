#!/usr/bin/env bash
set -euo pipefail

# Prints Hive access details (CLI + IDE/JDBC) using dynamic host-port mapping.
# Intended to run inside the Data Lab container from ~/hive/scripts/.

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

hive_jdbc_port="$(mapped_port 10000)"
hive_http_port="$(mapped_port 10001)"
yarn_ui_port="$(mapped_port 8088)"
hdfs_ui_port="$(mapped_port 9870)"

hive_user="$(prompt_default "Hive username" "datalab")"
hive_pass="$(prompt_default "Hive password (blank for noSasl)" "")"
hive_db="$(prompt_default "Hive database" "default")"

echo ""
echo "=== Hive Access Guide ==="
echo "Host-side endpoints are shown using dynamic mapped ports."
echo ""

echo "=== Required services ==="
echo "From inside container, start Hive stack:"
echo "  datalab_app --start-hive"
echo "or full core stack:"
echo "  datalab_app --start-core"
echo ""

echo "=== Browser UIs (host machine) ==="
echo "YARN ResourceManager:  http://${UI_HOST}:${yarn_ui_port}/"
echo "HDFS NameNode:         http://${UI_HOST}:${hdfs_ui_port}/"
echo ""

echo "=== CLI (inside container) ==="
echo "hivecli"
echo "hivelegacy"
echo "beeline -u 'jdbc:hive2://localhost:10001/${hive_db};transportMode=http;httpPath=cliservice;auth=noSasl' -n ${hive_user} -p ''"
echo ""

echo "=== IDE / JDBC (DBeaver / DataGrip / SQL tools) ==="
echo "Connection mode: HiveServer2 JDBC over HTTP"
echo "Host:      ${UI_HOST}"
echo "Port:      ${hive_http_port}"
echo "Database:  ${hive_db}"
echo "Username:  ${hive_user}"
if [[ -n "${hive_pass}" ]]; then
  echo "Password:  ${hive_pass}"
else
  echo "Password:  (blank)"
fi
echo "Auth:      noSasl"
echo "HTTP Path: cliservice"
echo ""
echo "JDBC URL:"
echo "  jdbc:hive2://${UI_HOST}:${hive_http_port}/${hive_db};transportMode=http;httpPath=cliservice;auth=noSasl"
echo ""

echo "=== Optional binary thrift endpoint ==="
echo "Host: ${UI_HOST}"
echo "Port: ${hive_jdbc_port} (HiveServer2 binary)"
echo "URL:  jdbc:hive2://${UI_HOST}:${hive_jdbc_port}/${hive_db}"
echo ""
echo "Tip: Run this script again whenever container/port mapping changes."
