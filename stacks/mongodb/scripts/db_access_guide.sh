#!/usr/bin/env bash
set -euo pipefail

# Prints DB UI + IDE connection values using dynamic host-port mapping.
# Intended to run inside the Data Lab container from ~/mongodb/scripts/.

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
adminer_port="$(mapped_port 8082)"
mongo_express_port="$(mapped_port 8083)"
redis_commander_port="$(mapped_port 8084)"

echo "=== Data Lab DB Access Guide ==="
echo "This guide shows host-side URLs and IDE connection values."
echo ""

pg_user="$(prompt_default "PostgreSQL username" "admin")"
pg_pass="$(prompt_default "PostgreSQL password" "admin")"
mongo_user="$(prompt_default "MongoDB username" "datalab")"
mongo_pass="$(prompt_default "MongoDB password" "datalab")"
redis_pass="$(prompt_default "Redis password (blank if none)" "")"

echo ""
echo "=== Browser UIs (host machine) ==="
echo "Adminer:               http://${UI_HOST}:${adminer_port}/"
echo "Mongo Express:         http://${UI_HOST}:${mongo_express_port}/"
echo "Redis Commander:       http://${UI_HOST}:${redis_commander_port}/"
echo "pgAdmin (if started):  http://${UI_HOST}:8181/"
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
echo "Tip: Run this again any time after container/port changes."
