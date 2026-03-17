#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

CDC_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CDC_SCRIPT_DIR}/../common.sh"

if ! declare -F kafka::start >/dev/null 2>&1; then
  source "${CDC_SCRIPT_DIR}/../kafka/manage.sh"
fi
if ! declare -F kafka_connect::start >/dev/null 2>&1; then
  source "${CDC_SCRIPT_DIR}/../kafka_connect/manage.sh"
fi
if ! declare -F postgres::ensure_cdc_ready >/dev/null 2>&1; then
  source "${CDC_SCRIPT_DIR}/../postgres/manage.sh"
fi
if ! declare -F schema_registry::start >/dev/null 2>&1; then
  source "${CDC_SCRIPT_DIR}/../schema_registry/manage.sh"
fi

CDC_BASE="${RUNTIME_ROOT}/cdc"
CDC_LOG_DIR="${CDC_BASE}/logs"
CDC_CONFIG_DIR="${CDC_BASE}/configs"
CDC_SOURCE_MODE="${CDC_SOURCE_MODE:-json}"
CDC_SOURCE_MODE="$(strip_cr "${CDC_SOURCE_MODE}")"
case "${CDC_SOURCE_MODE}" in
  json)
    CDC_MODE_SUFFIX=""
    ;;
  registry)
    CDC_MODE_SUFFIX="-registry"
    ;;
  *)
    echo "[!] Unsupported CDC_SOURCE_MODE='${CDC_SOURCE_MODE}'. Use 'json' or 'registry'." >&2
    exit 1
    ;;
esac

CDC_CONNECTOR_NAME="${CDC_CONNECTOR_NAME:-datalab-postgres-cdc${CDC_MODE_SUFFIX}}"
CDC_SOURCE_DB="${CDC_SOURCE_DB:-${POSTGRES_DB:-datalab}}"
CDC_SOURCE_SCHEMA="${CDC_SOURCE_SCHEMA:-public}"
CDC_SOURCE_TABLE="${CDC_SOURCE_TABLE:-customer_events}"
CDC_TOPIC_PREFIX="${CDC_TOPIC_PREFIX:-datalab_cdc${CDC_MODE_SUFFIX}}"
CDC_SLOT_NAME="${CDC_SLOT_NAME:-${POSTGRES_CDC_SLOT}${CDC_MODE_SUFFIX//-/_}}"
CDC_PUBLICATION_NAME="${CDC_PUBLICATION_NAME:-${POSTGRES_CDC_PUBLICATION}${CDC_MODE_SUFFIX//-/_}}"
CDC_TEMPLATE_DIR="${WORKSPACE}/kafka/connectors"
CDC_BASIC_TEMPLATE="${CDC_BASIC_TEMPLATE:-${CDC_TEMPLATE_DIR}/postgres-cdc-basic.json}"
CDC_REGISTRY_TEMPLATE="${CDC_REGISTRY_TEMPLATE:-${CDC_TEMPLATE_DIR}/postgres-cdc-registry.json}"
CDC_BASIC_CONFIG_FILE="${CDC_CONFIG_DIR}/postgres-cdc-basic.json"
CDC_REGISTRY_CONFIG_FILE="${CDC_CONFIG_DIR}/postgres-cdc-registry.json"

CDC_CONNECTOR_NAME="$(strip_cr "${CDC_CONNECTOR_NAME}")"
CDC_SOURCE_DB="$(strip_cr "${CDC_SOURCE_DB}")"
CDC_SOURCE_SCHEMA="$(strip_cr "${CDC_SOURCE_SCHEMA}")"
CDC_SOURCE_TABLE="$(strip_cr "${CDC_SOURCE_TABLE}")"
CDC_TOPIC_PREFIX="$(strip_cr "${CDC_TOPIC_PREFIX}")"
CDC_SLOT_NAME="$(strip_cr "${CDC_SLOT_NAME}")"
CDC_PUBLICATION_NAME="$(strip_cr "${CDC_PUBLICATION_NAME}")"
CDC_TEMPLATE_DIR="$(strip_cr "${CDC_TEMPLATE_DIR}")"
CDC_BASIC_TEMPLATE="$(strip_cr "${CDC_BASIC_TEMPLATE}")"
CDC_REGISTRY_TEMPLATE="$(strip_cr "${CDC_REGISTRY_TEMPLATE}")"
CDC_BASIC_CONFIG_FILE="$(strip_cr "${CDC_BASIC_CONFIG_FILE}")"
CDC_REGISTRY_CONFIG_FILE="$(strip_cr "${CDC_REGISTRY_CONFIG_FILE}")"

cdc::ensure_dirs() {
  mkdir -p "${CDC_BASE}" "${CDC_LOG_DIR}" "${CDC_CONFIG_DIR}"
}

cdc::table_fq() {
  printf '%s.%s' "${CDC_SOURCE_SCHEMA}" "${CDC_SOURCE_TABLE}"
}

cdc::topic_name() {
  printf '%s.%s.%s' "${CDC_TOPIC_PREFIX}" "${CDC_SOURCE_SCHEMA}" "${CDC_SOURCE_TABLE}"
}

cdc::schema_registry_url() {
  printf 'http://127.0.0.1:%s/apis/registry/v3' "${SCHEMA_REGISTRY_PORT:-8085}"
}

cdc::connector_status_url() {
  printf 'http://127.0.0.1:%s/connectors/%s/status' "${KAFKA_CONNECT_PORT:-8086}" "${CDC_CONNECTOR_NAME}"
}

cdc::connector_config_url() {
  printf 'http://127.0.0.1:%s/connectors/%s/config' "${KAFKA_CONNECT_PORT:-8086}" "${CDC_CONNECTOR_NAME}"
}

cdc::connectors_url() {
  printf 'http://127.0.0.1:%s/connectors' "${KAFKA_CONNECT_PORT:-8086}"
}

cdc::connector_plugins_url() {
  printf 'http://127.0.0.1:%s/connector-plugins' "${KAFKA_CONNECT_PORT:-8086}"
}

cdc::escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

cdc::require_template() {
  local file="$1"
  if [[ ! -f "${file}" ]]; then
    echo "[!] Missing CDC template: ${file}" >&2
    return 1
  fi
}

cdc::config_file_for_mode() {
  case "${CDC_SOURCE_MODE}" in
    json)
      printf '%s' "${CDC_BASIC_CONFIG_FILE}"
      ;;
    registry)
      printf '%s' "${CDC_REGISTRY_CONFIG_FILE}"
      ;;
    *)
      echo "[!] Unsupported CDC_SOURCE_MODE='${CDC_SOURCE_MODE}'. Use 'json' or 'registry'." >&2
      return 1
      ;;
  esac
}

cdc::template_for_mode() {
  case "${CDC_SOURCE_MODE}" in
    json)
      printf '%s' "${CDC_BASIC_TEMPLATE}"
      ;;
    registry)
      printf '%s' "${CDC_REGISTRY_TEMPLATE}"
      ;;
    *)
      echo "[!] Unsupported CDC_SOURCE_MODE='${CDC_SOURCE_MODE}'. Use 'json' or 'registry'." >&2
      return 1
      ;;
  esac
}

cdc::render_connector_config() {
  local template_file output_file table_include_list registry_url
  template_file="$(cdc::template_for_mode)"
  output_file="$(cdc::config_file_for_mode)"
  table_include_list="$(cdc::table_fq)"
  registry_url="$(cdc::schema_registry_url)"

  cdc::require_template "${template_file}"
  cdc::ensure_dirs

  sed \
    -e "s|__POSTGRES_HOST__|127.0.0.1|g" \
    -e "s|__POSTGRES_PORT__|$(cdc::escape_sed "${POSTGRES_PORT}")|g" \
    -e "s|__POSTGRES_DB__|$(cdc::escape_sed "${CDC_SOURCE_DB}")|g" \
    -e "s|__POSTGRES_USER__|$(cdc::escape_sed "${POSTGRES_CDC_USER}")|g" \
    -e "s|__POSTGRES_PASSWORD__|$(cdc::escape_sed "${POSTGRES_CDC_PASSWORD}")|g" \
    -e "s|__TOPIC_PREFIX__|$(cdc::escape_sed "${CDC_TOPIC_PREFIX}")|g" \
    -e "s|__SLOT_NAME__|$(cdc::escape_sed "${CDC_SLOT_NAME}")|g" \
    -e "s|__PUBLICATION_NAME__|$(cdc::escape_sed "${CDC_PUBLICATION_NAME}")|g" \
    -e "s|__TABLE_INCLUDE_LIST__|$(cdc::escape_sed "${table_include_list}")|g" \
    -e "s|__SCHEMA_REGISTRY_URL__|$(cdc::escape_sed "${registry_url}")|g" \
    "${template_file}" > "${output_file}"

  printf '%s' "${output_file}"
}

cdc::connect_foundation() {
  postgres::ensure_cdc_ready
  kafka::start
  schema_registry::start
  kafka_connect::start
}

cdc::plugin_ready() {
  curl -fsS "$(cdc::connector_plugins_url)" 2>/dev/null | grep -q 'io.debezium.connector.postgresql.PostgresConnector'
}

cdc::wait_for_plugin() {
  local deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if cdc::plugin_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

cdc::registry_converter_ready() {
  [[ -d "${KAFKA_HOME}/plugins/apicurio-registry-converter" ]]
}

cdc::connector_exists() {
  curl -fsS "$(cdc::connectors_url)" 2>/dev/null | grep -q "\"${CDC_CONNECTOR_NAME}\""
}

cdc::connector_running() {
  curl -fsS "$(cdc::connector_status_url)" 2>/dev/null | python3 -c '
import json, sys

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(1)

connector = payload.get("connector", {})
tasks = payload.get("tasks", [])
if connector.get("state") != "RUNNING":
    sys.exit(1)
if not tasks:
    sys.exit(1)
if any(task.get("state") != "RUNNING" for task in tasks):
    sys.exit(1)
sys.exit(0)
'
}

cdc::wait_for_connector() {
  local deadline=$((SECONDS + 90))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if cdc::connector_running; then
      return 0
    fi
    sleep 1
  done
  return 1
}

cdc::topic_ready() {
  "${KAFKA_HOME}/bin/kafka-topics.sh" --bootstrap-server "localhost:${KAFKA_BROKER_PORT}" --list 2>/dev/null | grep -Fxq "$(cdc::topic_name)"
}

cdc::wait_for_topic() {
  local deadline=$((SECONDS + 90))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if cdc::topic_ready; then
      return 0
    fi
    sleep 1
  done
  return 1
}

cdc::create_demo_table() {
  "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d "${CDC_SOURCE_DB}" -v ON_ERROR_STOP=1 <<EOF >/dev/null
DROP TABLE IF EXISTS $(cdc::table_fq);
CREATE TABLE $(cdc::table_fq) (
  id integer PRIMARY KEY,
  customer_name text NOT NULL,
  status text NOT NULL,
  amount numeric(10,2) NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE $(cdc::table_fq) OWNER TO ${POSTGRES_CDC_USER};
GRANT SELECT ON $(cdc::table_fq) TO ${POSTGRES_CDC_USER};
INSERT INTO $(cdc::table_fq) (id, customer_name, status, amount)
VALUES
  (1, 'Alice', 'new', 125.50),
  (2, 'Bob', 'new', 210.00);
EOF
}

cdc::apply_demo_changes() {
  "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d "${CDC_SOURCE_DB}" -v ON_ERROR_STOP=1 <<EOF >/dev/null
INSERT INTO $(cdc::table_fq) (id, customer_name, status, amount)
VALUES (3, 'Carol', 'new', 98.25)
ON CONFLICT (id) DO UPDATE
SET customer_name = EXCLUDED.customer_name,
    status = EXCLUDED.status,
    amount = EXCLUDED.amount,
    updated_at = now();

UPDATE $(cdc::table_fq)
SET status = 'processed',
    amount = 140.75,
    updated_at = now()
WHERE id = 1;
EOF
}

cdc::register_connector() {
  local config_file="$1"
  curl -fsS -X PUT "$(cdc::connector_config_url)" \
    -H 'Content-Type: application/json' \
    --data @"${config_file}" >/dev/null
}

cdc::drop_publication_and_slot() {
  "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d "${CDC_SOURCE_DB}" -v ON_ERROR_STOP=1 <<EOF >/dev/null
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = '${CDC_PUBLICATION_NAME}') THEN
    EXECUTE 'DROP PUBLICATION ${CDC_PUBLICATION_NAME}';
  END IF;
END
\$\$;
DO \$\$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = '${CDC_SLOT_NAME}' AND active = false) THEN
    PERFORM pg_drop_replication_slot('${CDC_SLOT_NAME}');
  END IF;
END
\$\$;
EOF
}

cdc::delete_connector() {
  curl -fsS -X DELETE "$(cdc::connectors_url)/${CDC_CONNECTOR_NAME}" >/dev/null 2>&1 || true
}

cdc::delete_topic() {
  "${KAFKA_HOME}/bin/kafka-topics.sh" \
    --bootstrap-server "localhost:${KAFKA_BROKER_PORT}" \
    --delete \
    --topic "$(cdc::topic_name)" >/dev/null 2>&1 || true
}

cdc::reset_postgres_demo() {
  postgres::start
  kafka::start
  kafka_connect::start
  cdc::delete_connector
  sleep 2
  cdc::delete_topic
  "${POSTGRES_PSQL_BIN}" -h "${POSTGRES_BASE}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d "${CDC_SOURCE_DB}" -c "DROP TABLE IF EXISTS $(cdc::table_fq);" >/dev/null 2>&1 || true
  cdc::drop_publication_and_slot || true
  echo "[+] PostgreSQL CDC demo connector and source table reset."
}

cdc::print_connector_status() {
  local url
  url="$(cdc::connector_status_url)"
  if ! curl -fsS "${url}" 2>/dev/null | python3 -c '
import json, sys

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(1)

connector = payload.get("connector", {})
tasks = payload.get("tasks", [])
print("Connector:", payload.get("name", "(unknown)"))
print("Connector state:", connector.get("state", "UNKNOWN"))
for task in tasks:
    print("Task {}: {}".format(task.get("id", "?"), task.get("state", "UNKNOWN")))
'
  then
    echo "Connector: ${CDC_CONNECTOR_NAME}"
    echo "Connector state: not available"
  fi
}

cdc::print_topic_messages() {
  local max_messages="${1:-6}"
  if ! cdc::topic_ready; then
    echo "[!] CDC topic $(cdc::topic_name) is not available yet." >&2
    return 1
  fi

  timeout 20s "${KAFKA_HOME}/bin/kafka-console-consumer.sh" \
    --bootstrap-server "localhost:${KAFKA_BROKER_PORT}" \
    --topic "$(cdc::topic_name)" \
    --from-beginning \
    --max-messages "${max_messages}" 2>/dev/null || true
}

cdc::setup_postgres_demo() {
  local config_file

  cdc::connect_foundation
  if ! cdc::wait_for_plugin; then
    echo "[!] Kafka Connect is running, but the Debezium PostgreSQL connector plugin is missing." >&2
    return 1
  fi

  if [[ "${CDC_SOURCE_MODE}" == "registry" ]] && ! cdc::registry_converter_ready; then
    echo "[!] Registry mode requested, but the Apicurio Kafka Connect converters are not bundled in the image." >&2
    return 1
  fi

  cdc::delete_connector
  sleep 2
  cdc::drop_publication_and_slot || true
  cdc::create_demo_table
  config_file="$(cdc::render_connector_config)"
  cdc::register_connector "${config_file}"

  if ! cdc::wait_for_connector; then
    echo "[!] PostgreSQL CDC connector failed to reach RUNNING state." >&2
    cdc::print_connector_status
    return 1
  fi

  cdc::apply_demo_changes
  if ! cdc::wait_for_topic; then
    echo "[!] CDC topic $(cdc::topic_name) was not created." >&2
    return 1
  fi

  echo "[+] PostgreSQL CDC demo is ready."
  echo "Connector: ${CDC_CONNECTOR_NAME}"
  echo "Mode: ${CDC_SOURCE_MODE}"
  echo "Topic: $(cdc::topic_name)"
  echo "Config: ${config_file}"
}

cdc::verify_postgres_demo() {
  cdc::connect_foundation
  echo "=== PostgreSQL CDC Status ==="
  cdc::print_connector_status
  echo "Topic: $(cdc::topic_name)"
  if cdc::topic_ready; then
    echo "Topic state: available"
  else
    echo "Topic state: missing"
  fi
  echo
  echo "=== Sample CDC Messages ==="
  cdc::print_topic_messages 6
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cmd="${1:-setup}"
  case "${cmd}" in
    setup)
      cdc::setup_postgres_demo
      ;;
    verify)
      cdc::verify_postgres_demo
      ;;
    reset)
      cdc::reset_postgres_demo
      ;;
    *)
      echo "Usage: $0 {setup|verify|reset}" >&2
      exit 2
      ;;
  esac
fi
