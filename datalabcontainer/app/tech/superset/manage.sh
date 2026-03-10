#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

SUPERSET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SUPERSET_SCRIPT_DIR}/../common.sh"

SUPERSET_BASE="${RUNTIME_ROOT}/superset"
SUPERSET_HOME_DIR="${SUPERSET_BASE}/home"
SUPERSET_LOG_DIR="${SUPERSET_BASE}/logs"
SUPERSET_PID_DIR="${SUPERSET_BASE}/pids"
SUPERSET_DB_DIR="${SUPERSET_BASE}/db"
SUPERSET_CONFIG_FILE="${SUPERSET_BASE}/superset_config.py"
SUPERSET_PID_FILE="${SUPERSET_PID_DIR}/superset.pid"
SUPERSET_LOG_FILE="${SUPERSET_LOG_DIR}/superset.log"
SUPERSET_VENV="${SUPERSET_VENV:-/opt/superset-venv}"
SUPERSET_BIN="${SUPERSET_VENV}/bin/superset"

: "${SUPERSET_PORT:=8090}"
: "${SUPERSET_ADMIN_USERNAME:=admin}"
: "${SUPERSET_ADMIN_PASSWORD:=admin}"
: "${SUPERSET_ADMIN_FIRSTNAME:=Data}"
: "${SUPERSET_ADMIN_LASTNAME:=Lab}"
: "${SUPERSET_ADMIN_EMAIL:=admin@local}"
: "${SUPERSET_SECRET_KEY:=datalab-local-superset-secret-key-change-me}"
: "${SUPERSET_SQLLAB_BACKEND_PERSISTENCE:=True}"
: "${SUPERSET_TRINO_DB_NAME:=Trino Lakehouse}"
: "${TRINO_HOST:=localhost}"
: "${TRINO_PORT:=8091}"
: "${TRINO_USER:=trino}"
: "${TRINO_DEFAULT_CATALOG:=hive}"
: "${TRINO_DEFAULT_SCHEMA:=default}"
: "${SUPERSET_TRINO_MULTI_CATALOG:=True}"
: "${SUPERSET_TRINO_NEUTRAL_CATALOG:=hive}"
: "${SUPERSET_TRINO_NEUTRAL_SCHEMA:=default}"
: "${SUPERSET_TRINO_GUARD_LATEST_PARTITION:=True}"

superset::ensure_dirs() {
  mkdir -p "${SUPERSET_BASE}" "${SUPERSET_HOME_DIR}" "${SUPERSET_LOG_DIR}" "${SUPERSET_PID_DIR}" "${SUPERSET_DB_DIR}"
  if [[ "$(id -u)" -eq 0 ]]; then
    local app_user="${LAB_APP_USER:-datalab}"
    chown -R "${app_user}:${app_user}" "${SUPERSET_BASE}" 2>/dev/null || true
    chmod 777 "${SUPERSET_BASE}" "${SUPERSET_HOME_DIR}" "${SUPERSET_LOG_DIR}" "${SUPERSET_PID_DIR}" "${SUPERSET_DB_DIR}" 2>/dev/null || true
  fi
}

superset::pid_alive() {
  [[ -f "${SUPERSET_PID_FILE}" ]] && kill -0 "$(cat "${SUPERSET_PID_FILE}")" 2>/dev/null
}

superset::cleanup_stale_pid() {
  if [[ -f "${SUPERSET_PID_FILE}" ]] && ! superset::pid_alive; then
    rm -f "${SUPERSET_PID_FILE}"
  fi
}

superset::port_open() {
  local host="$1" port="$2"
  SUPERSET_WAIT_HOST="${host}" SUPERSET_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["SUPERSET_WAIT_HOST"]
port = int(os.environ["SUPERSET_WAIT_PORT"])
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

superset::wait_for_port() {
  local host="$1" port="$2" deadline
  deadline=$((SECONDS + 90))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if superset::port_open "${host}" "${port}"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

superset::write_config() {
  local db_path="${SUPERSET_DB_DIR}/superset.db"
  cat > "${SUPERSET_CONFIG_FILE}" <<EOF
import os
SECRET_KEY = os.environ.get("SUPERSET_SECRET_KEY", "${SUPERSET_SECRET_KEY}")
SQLALCHEMY_DATABASE_URI = "sqlite:///${db_path}"
WTF_CSRF_ENABLED = True
TALISMAN_ENABLED = False
FEATURE_FLAGS = {
    "SQLLAB_BACKEND_PERSISTENCE": ${SUPERSET_SQLLAB_BACKEND_PERSISTENCE},
}

# Guard SQL Lab "select table" against Trino Iceberg metadata-only partition indexes.
DATALAB_TRINO_GUARD_LATEST_PARTITION = str(
    os.environ.get(
        "SUPERSET_TRINO_GUARD_LATEST_PARTITION",
        "${SUPERSET_TRINO_GUARD_LATEST_PARTITION}",
    )
).lower() in ("1", "true", "yes", "on")


def _patch_trino_latest_partition_guard() -> None:
    try:
        from superset.db_engine_specs.trino import TrinoEngineSpec
    except Exception:
        return

    if getattr(TrinoEngineSpec, "_datalab_partition_guard_patched", False):
        return

    original_get_extra_table_metadata = TrinoEngineSpec.get_extra_table_metadata
    original_where_latest_partition = TrinoEngineSpec.where_latest_partition

    def _get_extra_table_metadata_guard(
        cls,
        database,
        table,
    ):
        try:
            metadata = original_get_extra_table_metadata(
                database,
                table,
            )
        except Exception:
            metadata = {}

        # SQL Lab table selection should not use Trino partition metadata here,
        # because Iceberg reports file-level fields (record_count, file_count, ...)
        # that are not real table columns.
        metadata.pop("partitions", None)
        return metadata

    def _where_latest_partition_guard(
        cls,
        database,
        table,
        query,
        columns=None,
    ):
        # Always keep table-preview SQL as plain SELECT * ... LIMIT for Trino.
        return query

    TrinoEngineSpec.get_extra_table_metadata = classmethod(
        _get_extra_table_metadata_guard
    )
    TrinoEngineSpec.where_latest_partition = classmethod(
        _where_latest_partition_guard
    )
    TrinoEngineSpec._datalab_partition_guard_patched = True


def FLASK_APP_MUTATOR(app) -> None:
    if DATALAB_TRINO_GUARD_LATEST_PARTITION:
        _patch_trino_latest_partition_guard()
EOF
}

superset::bootstrap_metadata() {
  env \
    FLASK_APP="superset" \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    "${SUPERSET_BIN}" db upgrade >/dev/null

  env \
    FLASK_APP="superset" \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    "${SUPERSET_BIN}" fab create-admin \
      --username "${SUPERSET_ADMIN_USERNAME}" \
      --firstname "${SUPERSET_ADMIN_FIRSTNAME}" \
      --lastname "${SUPERSET_ADMIN_LASTNAME}" \
      --email "${SUPERSET_ADMIN_EMAIL}" \
      --password "${SUPERSET_ADMIN_PASSWORD}" >/dev/null 2>&1 || true

  env \
    FLASK_APP="superset" \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    "${SUPERSET_BIN}" init >/dev/null
}

superset::ensure_trino_database() {
  local trino_uri
  if [[ "${SUPERSET_TRINO_MULTI_CATALOG,,}" == "true" ]]; then
    # Use neutral shared-metastore catalog for UI schema browsing.
    trino_uri="trino://${TRINO_USER}@${TRINO_HOST}:${TRINO_PORT}/${SUPERSET_TRINO_NEUTRAL_CATALOG}/${SUPERSET_TRINO_NEUTRAL_SCHEMA}"
  else
    trino_uri="trino://${TRINO_USER}@${TRINO_HOST}:${TRINO_PORT}/${TRINO_DEFAULT_CATALOG}/${TRINO_DEFAULT_SCHEMA}"
  fi
  env \
    FLASK_APP="superset" \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    "${SUPERSET_BIN}" set-database-uri \
      -d "${SUPERSET_TRINO_DB_NAME}" \
      -u "${trino_uri}" >/dev/null 2>&1 || true

  python3 - <<PY
import sqlite3
db_path = "${SUPERSET_DB_DIR}/superset.db"
conn = sqlite3.connect(db_path)
cur = conn.cursor()
cur.execute("UPDATE dbs SET allow_dml = 1 WHERE database_name = ?", ("${SUPERSET_TRINO_DB_NAME}",))
for legacy in ("Trino Iceberg", "Trino Delta", "Trino Hudi"):
    cur.execute("DELETE FROM dbs WHERE database_name = ?", (legacy,))
conn.commit()
conn.close()
PY
}

superset::start() {
  superset::ensure_dirs
  superset::cleanup_stale_pid
  superset::write_config

  if [[ ! -x "${SUPERSET_BIN}" ]]; then
    echo "[!] Superset binary not found at ${SUPERSET_BIN}; rebuild image." >&2
    return 1
  fi

  if superset::pid_alive && superset::port_open localhost "${SUPERSET_PORT}"; then
    echo "[*] Superset already running (PID $(cat "${SUPERSET_PID_FILE}"))."
    return 0
  fi

  superset::bootstrap_metadata
  superset::ensure_trino_database
  pkill -f "${SUPERSET_VENV}/bin/superset run" >/dev/null 2>&1 || true
  echo "[*] Starting Superset on $(common::ui_url "${SUPERSET_PORT}" "/")..."
  env \
    SUPERSET_HOME="${SUPERSET_HOME_DIR}" \
    SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_FILE}" \
    SUPERSET_SECRET_KEY="${SUPERSET_SECRET_KEY}" \
    FLASK_APP="superset" \
    nohup "${SUPERSET_BIN}" run -p "${SUPERSET_PORT}" -h 0.0.0.0 \
      > "${SUPERSET_LOG_FILE}" 2>&1 &
  echo $! > "${SUPERSET_PID_FILE}"

  if ! superset::wait_for_port localhost "${SUPERSET_PORT}"; then
    echo "[!] Superset failed to open port ${SUPERSET_PORT}; see ${SUPERSET_LOG_FILE}" >&2
    return 1
  fi
  echo "[+] Superset started (PID $(cat "${SUPERSET_PID_FILE}"))."
}

superset::stop() {
  superset::cleanup_stale_pid
  if superset::pid_alive; then
    kill "$(cat "${SUPERSET_PID_FILE}")" 2>/dev/null || true
  fi
  pkill -f "${SUPERSET_VENV}/bin/superset run" >/dev/null 2>&1 || true
  rm -f "${SUPERSET_PID_FILE}"
  echo "[+] Superset stopped."
}

superset::status() {
  if superset::pid_alive && superset::port_open localhost "${SUPERSET_PORT}"; then
    echo "[+] Superset: $(common::ui_url "${SUPERSET_PORT}" "/")"
  else
    echo "[-] Superset: not running"
  fi
}
