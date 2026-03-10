#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

TRINO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${TRINO_SCRIPT_DIR}/../common.sh"

TRINO_HOME="${TRINO_HOME:-/opt/trino}"
TRINO_RUNTIME_BASE="${RUNTIME_ROOT}/trino"
TRINO_ETC_DIR="${TRINO_RUNTIME_BASE}/etc"
TRINO_DATA_DIR="${TRINO_RUNTIME_BASE}/data"
TRINO_LOG_DIR="${TRINO_RUNTIME_BASE}/logs"
TRINO_PID_DIR="${TRINO_RUNTIME_BASE}/pids"
TRINO_TEMPLATE_ETC="${TRINO_TEMPLATE_ETC:-/opt/trino/etc-template}"
TRINO_JAVA_HOME="${TRINO_JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"

TRINO_PORT="${TRINO_PORT:-8091}"
TRINO_USER="${TRINO_USER:-trino}"
TRINO_PID_FILE="${TRINO_PID_DIR}/trino.pid"
TRINO_LOG_FILE="${TRINO_LOG_DIR}/trino.log"
TRINO_LAUNCHER_PID_FILE="${TRINO_DATA_DIR}/var/run/launcher.pid"
LAKEHOUSE_STACK_ROOT="${LAKEHOUSE_STACK_ROOT:-}"
ICEBERG_TRINO_SCHEMA_SQL="${ICEBERG_TRINO_SCHEMA_SQL:-}"
ICEBERG_TRINO_TABLE_SQL="${ICEBERG_TRINO_TABLE_SQL:-}"
DELTA_TRINO_SCHEMA_SQL="${DELTA_TRINO_SCHEMA_SQL:-}"
DELTA_SPARK_TABLE_SQL="${DELTA_SPARK_TABLE_SQL:-}"
DELTA_TRINO_REGISTER_SQL="${DELTA_TRINO_REGISTER_SQL:-}"
HUDI_TRINO_SCHEMA_SQL="${HUDI_TRINO_SCHEMA_SQL:-}"
HUDI_SPARK_TABLE_SQL="${HUDI_SPARK_TABLE_SQL:-}"

trino::ensure_dirs() {
  local required_file=""
  local required_files=(
    "config.properties"
    "jvm.config"
    "node.properties"
    "catalog/hive.properties"
    "catalog/iceberg.properties"
    "catalog/delta.properties"
    "catalog/hudi.properties"
  )
  mkdir -p "${TRINO_ETC_DIR}" "${TRINO_DATA_DIR}" "${TRINO_LOG_DIR}" "${TRINO_PID_DIR}"
  if [[ -d "${TRINO_TEMPLATE_ETC}" ]]; then
    # Seed runtime config without overwriting user-edited runtime files.
    cp -rn "${TRINO_TEMPLATE_ETC}/." "${TRINO_ETC_DIR}/" 2>/dev/null || true
    for required_file in "${required_files[@]}"; do
      if [[ ! -f "${TRINO_ETC_DIR}/${required_file}" ]] && [[ -f "${TRINO_TEMPLATE_ETC}/${required_file}" ]]; then
        mkdir -p "$(dirname "${TRINO_ETC_DIR}/${required_file}")"
        cp "${TRINO_TEMPLATE_ETC}/${required_file}" "${TRINO_ETC_DIR}/${required_file}"
      fi
    done
  fi
  for required_file in "${required_files[@]}"; do
    if [[ ! -f "${TRINO_ETC_DIR}/${required_file}" ]]; then
      echo "[!] Missing Trino config file: ${TRINO_ETC_DIR}/${required_file}" >&2
      echo "[!] Ensure lakehouse template exists at ${TRINO_TEMPLATE_ETC} and rebuild image if needed." >&2
      return 1
    fi
  done
  # Keep Delta compatibility flags enabled even for upgraded containers with stale runtime config.
  if [[ -f "${TRINO_ETC_DIR}/catalog/delta.properties" ]] && ! grep -q '^delta\.enable-non-concurrent-writes=' "${TRINO_ETC_DIR}/catalog/delta.properties"; then
    echo "delta.enable-non-concurrent-writes=true" >> "${TRINO_ETC_DIR}/catalog/delta.properties"
  fi
  if [[ -f "${TRINO_ETC_DIR}/catalog/delta.properties" ]] && ! grep -q '^delta\.register-table-procedure\.enabled=' "${TRINO_ETC_DIR}/catalog/delta.properties"; then
    echo "delta.register-table-procedure.enabled=true" >> "${TRINO_ETC_DIR}/catalog/delta.properties"
  fi
  # Enable one-catalog schema.table access through hive with table-type redirection.
  if [[ -f "${TRINO_ETC_DIR}/catalog/hive.properties" ]] && ! grep -q '^hive\.iceberg-catalog-name=' "${TRINO_ETC_DIR}/catalog/hive.properties"; then
    echo "hive.iceberg-catalog-name=iceberg" >> "${TRINO_ETC_DIR}/catalog/hive.properties"
  fi
  if [[ -f "${TRINO_ETC_DIR}/catalog/hive.properties" ]] && ! grep -q '^hive\.delta-lake-catalog-name=' "${TRINO_ETC_DIR}/catalog/hive.properties"; then
    echo "hive.delta-lake-catalog-name=delta" >> "${TRINO_ETC_DIR}/catalog/hive.properties"
  fi
  if [[ -f "${TRINO_ETC_DIR}/catalog/hive.properties" ]] && ! grep -q '^hive\.hudi-catalog-name=' "${TRINO_ETC_DIR}/catalog/hive.properties"; then
    echo "hive.hudi-catalog-name=hudi" >> "${TRINO_ETC_DIR}/catalog/hive.properties"
  fi
  if [[ -f "${TRINO_ETC_DIR}/node.properties" ]]; then
    sed -i "s|^node.data-dir=.*$|node.data-dir=${TRINO_DATA_DIR}|" "${TRINO_ETC_DIR}/node.properties" || true
    sed -i "s|^node.id=.*$|node.id=trino-$(hostname)|" "${TRINO_ETC_DIR}/node.properties" || true
  fi
  if [[ "$(id -u)" -eq 0 ]]; then
    local app_user="${LAB_APP_USER:-datalab}"
    chown -R "${app_user}:${app_user}" "${TRINO_RUNTIME_BASE}" 2>/dev/null || true
    chmod -R u+rwX,go+rX "${TRINO_RUNTIME_BASE}" 2>/dev/null || true
  fi
}

trino::pid_alive() {
  [[ -f "${TRINO_PID_FILE}" ]] && kill -0 "$(cat "${TRINO_PID_FILE}")" 2>/dev/null
}

trino::port_open() {
  local host="$1" port="$2"
  DBUI_WAIT_HOST="${host}" DBUI_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["DBUI_WAIT_HOST"]
port = int(os.environ["DBUI_WAIT_PORT"])
s = socket.socket()
s.settimeout(1)
try:
    s.connect((host, port))
except OSError:
    sys.exit(1)
else:
    s.close()
    sys.exit(0)
PY
}

trino::wait_for_port() {
  local host="$1" port="$2" deadline
  deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if trino::port_open "${host}" "${port}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

trino::resolve_lakehouse_root() {
  common::resolve_lakehouse_root
}

trino::prepare_demo_sql_paths() {
  local root
  root="$(common::require_lakehouse_root || true)"
  if [[ -z "${root}" ]]; then
    return 1
  fi

  [[ -z "${ICEBERG_TRINO_SCHEMA_SQL}" ]] && ICEBERG_TRINO_SCHEMA_SQL="${root}/iceberg/sql/01-create-schema-trino.sql"
  [[ -z "${ICEBERG_TRINO_TABLE_SQL}" ]] && ICEBERG_TRINO_TABLE_SQL="${root}/iceberg/sql/02-create-table-trino.sql"
  [[ -z "${DELTA_TRINO_SCHEMA_SQL}" ]] && DELTA_TRINO_SCHEMA_SQL="${root}/delta/sql/01-create-schema-trino.sql"
  [[ -z "${DELTA_SPARK_TABLE_SQL}" ]] && DELTA_SPARK_TABLE_SQL="${root}/delta/sql/02-create-table-spark.sql"
  [[ -z "${DELTA_TRINO_REGISTER_SQL}" ]] && DELTA_TRINO_REGISTER_SQL="${root}/delta/sql/03-register-table-trino.sql"
  [[ -z "${HUDI_TRINO_SCHEMA_SQL}" ]] && HUDI_TRINO_SCHEMA_SQL="${root}/hudi/sql/01-create-schema-trino.sql"
  [[ -z "${HUDI_SPARK_TABLE_SQL}" ]] && HUDI_SPARK_TABLE_SQL="${root}/hudi/sql/02-create-table-spark.sql"
}

trino::require_demo_sql_assets() {
  local file=""
  local required=(
    "${ICEBERG_TRINO_SCHEMA_SQL}"
    "${ICEBERG_TRINO_TABLE_SQL}"
    "${DELTA_TRINO_SCHEMA_SQL}"
    "${DELTA_SPARK_TABLE_SQL}"
    "${DELTA_TRINO_REGISTER_SQL}"
    "${HUDI_TRINO_SCHEMA_SQL}"
    "${HUDI_SPARK_TABLE_SQL}"
  )
  for file in "${required[@]}"; do
    if [[ ! -f "${file}" ]]; then
      echo "[!] Missing lakehouse demo SQL asset: ${file}" >&2
      return 1
    fi
  done
}

trino::start() {
  trino::ensure_dirs
  if [[ ! -x "${TRINO_HOME}/bin/launcher" ]]; then
    echo "[!] Trino launcher not found at ${TRINO_HOME}/bin/launcher; rebuild image." >&2
    return 1
  fi

  if trino::pid_alive && trino::port_open localhost "${TRINO_PORT}"; then
    echo "[*] Trino already running (PID $(cat "${TRINO_PID_FILE}"))."
    return 0
  fi

  pkill -f "io.trino.server.TrinoServer" >/dev/null 2>&1 || true
  rm -f "${TRINO_PID_FILE}" "${TRINO_LAUNCHER_PID_FILE}"
  echo "[*] Starting Trino on $(common::ui_url "${TRINO_PORT}" "/")..."
  env JAVA_HOME="${TRINO_JAVA_HOME}" PATH="${TRINO_JAVA_HOME}/bin:${PATH}" nohup "${TRINO_HOME}/bin/launcher" run --etc-dir "${TRINO_ETC_DIR}" --launcher-log-file "${TRINO_LOG_FILE}" \
    > "${TRINO_LOG_FILE}" 2>&1 &
  echo $! > "${TRINO_PID_FILE}"
  if ! trino::wait_for_port localhost "${TRINO_PORT}"; then
    echo "[!] Trino failed to open port ${TRINO_PORT}; see ${TRINO_LOG_FILE}" >&2
    return 1
  fi
  echo "[+] Trino started (PID $(cat "${TRINO_PID_FILE}"))."
}

trino::stop() {
  if [[ -x "${TRINO_HOME}/bin/launcher" ]]; then
    env JAVA_HOME="${TRINO_JAVA_HOME}" PATH="${TRINO_JAVA_HOME}/bin:${PATH}" "${TRINO_HOME}/bin/launcher" stop >/dev/null 2>&1 || true
  fi
  if trino::pid_alive; then
    kill "$(cat "${TRINO_PID_FILE}")" 2>/dev/null || true
  fi
  pkill -f "io.trino.server.TrinoServer" >/dev/null 2>&1 || true
  rm -f "${TRINO_PID_FILE}" "${TRINO_LAUNCHER_PID_FILE}"
  echo "[+] Trino stopped."
}

trino::status() {
  if trino::pid_alive && trino::port_open localhost "${TRINO_PORT}"; then
    echo "[+] Trino: $(common::ui_url "${TRINO_PORT}" "/")"
  else
    echo "[-] Trino: not running"
  fi
}

trino::cli_exec() {
  local sql="${1:-}"
  if [[ -z "${sql}" ]]; then
    echo "[!] Missing SQL input for trino::cli_exec" >&2
    return 1
  fi
  if [[ -x "${TRINO_HOME}/bin/trino" ]]; then
    "${TRINO_HOME}/bin/trino" --server "localhost:${TRINO_PORT}" --user "${TRINO_USER}" --execute "${sql}"
    return 0
  fi

  TRINO_SQL="${sql}" TRINO_PORT="${TRINO_PORT}" TRINO_USER="${TRINO_USER}" \
  TRINO_CATALOG="${TRINO_CATALOG:-}" TRINO_SCHEMA="${TRINO_SCHEMA:-}" python3 - <<'PY'
import json
import os
import sys
import urllib.request
import urllib.error

sql = os.environ["TRINO_SQL"]
port = os.environ["TRINO_PORT"]
user = os.environ["TRINO_USER"]
catalog = os.environ.get("TRINO_CATALOG") or ""
schema = os.environ.get("TRINO_SCHEMA") or ""
base_url = f"http://localhost:{port}"
url = f"{base_url}/v1/statement"

req = urllib.request.Request(url, data=sql.encode("utf-8"), method="POST")
req.add_header("X-Trino-User", user)
req.add_header("Content-Type", "text/plain; charset=utf-8")
if catalog:
    req.add_header("X-Trino-Catalog", catalog)
if schema:
    req.add_header("X-Trino-Schema", schema)
try:
    with urllib.request.urlopen(req, timeout=20) as resp:
        payload = json.loads(resp.read().decode("utf-8"))
except urllib.error.HTTPError as exc:
    body = exc.read().decode("utf-8", errors="replace")
    print(f"[!] Trino HTTP query failed ({exc.code}): {body}", file=sys.stderr)
    sys.exit(1)
except Exception as exc:
    print(f"[!] Trino HTTP query failed: {exc}", file=sys.stderr)
    sys.exit(1)

while True:
    if payload.get("error"):
        message = payload["error"].get("message", "Unknown Trino error")
        print(f"[!] Trino query error: {message}", file=sys.stderr)
        sys.exit(1)

    next_uri = payload.get("nextUri")
    if not next_uri:
        break

    poll_req = urllib.request.Request(next_uri, method="GET")
    poll_req.add_header("X-Trino-User", user)
    try:
        with urllib.request.urlopen(poll_req, timeout=20) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        print(f"[!] Trino poll failed ({exc.code}): {body}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:
        print(f"[!] Trino poll failed: {exc}", file=sys.stderr)
        sys.exit(1)
PY
}

trino::hive_exec() {
  local sql="${1:-}"
  if [[ -z "${sql}" ]]; then
    echo "[!] Missing SQL input for trino::hive_exec" >&2
    return 1
  fi
  if command -v hive >/dev/null 2>&1; then
    hive -e "${sql}" >/dev/null
    return 0
  fi
  if [[ -x "/opt/hive/bin/hive" ]]; then
    /opt/hive/bin/hive -e "${sql}" >/dev/null
    return 0
  fi
  echo "[!] Hive CLI not found; cannot manage Hive Metastore schemas." >&2
  return 1
}

trino::exec_sql_file() {
  local file_path="${1:-}"
  local session_target="${2:-}"
  local raw_sql statement session_catalog session_schema
  if [[ -z "${file_path}" ]]; then
    echo "[!] Missing SQL file path for trino::exec_sql_file" >&2
    return 1
  fi
  if [[ ! -f "${file_path}" ]]; then
    echo "[!] SQL file not found: ${file_path}" >&2
    return 1
  fi

  # Trino HTTP endpoint handles one statement per request and rejects trailing ';'.
  raw_sql="$(awk '
    {
      sub(/\r$/, "", $0)
      if ($0 ~ /^[[:space:]]*--/) next
      print
    }
  ' "${file_path}" | tr '\n' ' ')"

  if [[ -n "${session_target}" ]]; then
    session_catalog="${session_target%%.*}"
    if [[ "${session_target}" == *.* ]]; then
      session_schema="${session_target#*.}"
    else
      session_schema=""
    fi
  fi

  while IFS= read -r statement; do
    statement="$(printf '%s' "${statement}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "${statement}" ]] && continue
    if [[ -n "${session_target}" ]]; then
      TRINO_CATALOG="${session_catalog}" TRINO_SCHEMA="${session_schema}" trino::cli_exec "${statement}"
    else
      trino::cli_exec "${statement}"
    fi
  done < <(printf '%s' "${raw_sql}" | tr ';' '\n')
}

trino::cleanup_demo_paths() {
  if [[ -x "${HDFS_BIN:-}" ]]; then
    "${HDFS_BIN}" dfs -rm -r -f -skipTrash /datalake/delta/demo_delta/orders_delta >/dev/null 2>&1 || true
    "${HDFS_BIN}" dfs -rm -r -f -skipTrash /datalake/delta/demo_delta/table_delta >/dev/null 2>&1 || true
    "${HDFS_BIN}" dfs -rm -r -f -skipTrash /datalake/hudi/demo_hudi/orders_hudi >/dev/null 2>&1 || true
    "${HDFS_BIN}" dfs -rm -r -f -skipTrash /datalake/hudi/demo_hudi/order_hudi >/dev/null 2>&1 || true
  else
    hdfs dfs -rm -r -f -skipTrash /datalake/delta/demo_delta/orders_delta >/dev/null 2>&1 || true
    hdfs dfs -rm -r -f -skipTrash /datalake/delta/demo_delta/table_delta >/dev/null 2>&1 || true
    hdfs dfs -rm -r -f -skipTrash /datalake/hudi/demo_hudi/orders_hudi >/dev/null 2>&1 || true
    hdfs dfs -rm -r -f -skipTrash /datalake/hudi/demo_hudi/order_hudi >/dev/null 2>&1 || true
  fi
}

trino::spark_sql_exec_file() {
  local file_path="${1:-}"
  local engine="${2:-generic}"
  local spark_sql_bin="${SPARK_HOME}/bin/spark-sql"
  local -a spark_args
  if [[ -z "${file_path}" ]]; then
    echo "[!] Missing SQL file path for trino::spark_sql_exec_file" >&2
    return 1
  fi
  if [[ ! -f "${file_path}" ]]; then
    echo "[!] Spark SQL file not found: ${file_path}" >&2
    return 1
  fi
  if [[ ! -x "${spark_sql_bin}" ]]; then
    echo "[!] spark-sql not found at ${spark_sql_bin}" >&2
    return 1
  fi

  case "${engine}" in
    delta)
      spark_args=(
        --conf "spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension"
        --conf "spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog"
      )
      ;;
    hudi)
      spark_args=(
        --conf "spark.serializer=org.apache.spark.serializer.KryoSerializer"
        --conf "spark.sql.extensions=org.apache.spark.sql.hudi.HoodieSparkSessionExtension"
        --conf "spark.sql.hive.convertMetastoreParquet=false"
        --conf "spark.hadoop.hoodie.embed.timeline.server=false"
        --conf "spark.hadoop.hoodie.metadata.enable=false"
        --conf "spark.sql.hudi.metadata.enabled=false"
      )
      ;;
    *)
      spark_args=()
      ;;
  esac

  "${spark_sql_bin}" "${spark_args[@]}" -f "${file_path}" >/dev/null
}

trino::cleanup_demo_schemas() {
  local schema
  local schemas=(
    demo_lakehouse
    bronze
    silver
    gold
    hudi_sync_test
    delta_lh_bronze
    delta_lh_silver
    delta_lh_gold
    hudi_lh_bronze
    hudi_lh_silver
    hudi_lh_gold
    iceberg_lh_bronze
    iceberg_lh_silver
    iceberg_lh_gold
    demo_iceberg
    demo_delta
    demo_hudi
    hudi
    delta
    iceberg
    testing
  )
  echo "[*] Cleaning legacy demo schemas..."
  for schema in "${schemas[@]}"; do
    trino::hive_exec "DROP DATABASE IF EXISTS ${schema} CASCADE;" || true
  done
}

trino::setup_simple_demo() {
  if ! trino::port_open localhost "${TRINO_PORT}"; then
    echo "[!] Trino is not reachable on port ${TRINO_PORT}. Start Trino first." >&2
    return 1
  fi
  trino::prepare_demo_sql_paths
  trino::require_demo_sql_assets

  trino::cleanup_demo_schemas
  trino::cleanup_demo_paths
  echo "[*] Applying Iceberg SQL assets..."
  trino::exec_sql_file "${ICEBERG_TRINO_SCHEMA_SQL}" "hive.default"
  trino::exec_sql_file "${ICEBERG_TRINO_TABLE_SQL}"

  echo "[*] Applying Delta SQL assets..."
  trino::exec_sql_file "${DELTA_TRINO_SCHEMA_SQL}" "hive.default"
  trino::spark_sql_exec_file "${DELTA_SPARK_TABLE_SQL}" "delta"
  trino::exec_sql_file "${DELTA_TRINO_REGISTER_SQL}"

  echo "[*] Applying Hudi SQL assets..."
  trino::exec_sql_file "${HUDI_TRINO_SCHEMA_SQL}" "hive.default"
  trino::spark_sql_exec_file "${HUDI_SPARK_TABLE_SQL}" "hudi"

  echo "[*] Demo check (single connection style via hive catalog + schema.table):"
  TRINO_CATALOG="hive" trino::cli_exec "SHOW TABLES FROM demo_iceberg"
  TRINO_CATALOG="hive" trino::cli_exec "SHOW TABLES FROM demo_delta"
  TRINO_CATALOG="hive" trino::cli_exec "SHOW TABLES FROM demo_hudi"
  echo "[+] Lakehouse SQL assets setup completed."
}

trino::lakehouse_tests() {
  local catalog
  if ! trino::port_open localhost "${TRINO_PORT}"; then
    echo "[!] Trino is not reachable on port ${TRINO_PORT}. Start Trino first." >&2
    return 1
  fi

  echo "[*] Running lakehouse smoke tests via Trino..."
  trino::cli_exec "SHOW CATALOGS" >/dev/null
  trino::cli_exec "SHOW SCHEMAS FROM hive" >/dev/null

  for catalog in iceberg delta hudi; do
    echo "[*] Test (${catalog}): catalog availability + schema listing"
    trino::cli_exec "SHOW SCHEMAS FROM ${catalog}" >/dev/null
    trino::cli_exec "SELECT '${catalog}' AS catalog_name, count(*) AS schema_count FROM ${catalog}.information_schema.schemata"
    echo "[+] ${catalog} test passed"
  done

  echo "[+] Lakehouse smoke tests passed (iceberg, delta, hudi)."
}
