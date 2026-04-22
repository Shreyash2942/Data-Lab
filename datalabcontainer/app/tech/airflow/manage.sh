#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"
if ! declare -F postgres::start >/dev/null 2>&1; then
  # Allows Airflow start to prepare metadata backend even when caller did not
  # source postgres helpers first.
  source "${SCRIPT_DIR}/../postgres/manage.sh"
fi

AIRFLOW_WEB_PID_FILE="${AIRFLOW_PID_DIR}/webserver.pid"
AIRFLOW_SCHED_PID_FILE="${AIRFLOW_PID_DIR}/scheduler.pid"
AIRFLOW_DEFAULT_USERNAME="${AIRFLOW_DEFAULT_USER:-${CONTAINER_NAME:-datalab}}"
AIRFLOW_DEFAULT_PASSWORD="${AIRFLOW_DEFAULT_PASS:-admin}"
AIRFLOW_DEFAULT_EMAIL="${AIRFLOW_DEFAULT_EMAIL:-${AIRFLOW_DEFAULT_USERNAME}@example.com}"
AIRFLOW_WEB_PORT="${AIRFLOW_WEB_PORT:-8080}"
: "${AIRFLOW_DB_NAME:=${POSTGRES_DB:-datalab}}"
: "${AIRFLOW_DB_USER:=${POSTGRES_USER:-admin}}"
: "${AIRFLOW_DB_PASSWORD:=${POSTGRES_PASSWORD:-admin}}"
: "${AIRFLOW_CORE_PARALLELISM:=16}"
: "${AIRFLOW_CORE_MAX_ACTIVE_TASKS_PER_DAG:=8}"
: "${AIRFLOW_CORE_MAX_ACTIVE_RUNS_PER_DAG:=4}"
: "${AIRFLOW_HOME:=${RUNTIME_ROOT}/airflow}"
: "${AIRFLOW_CONFIG:=${AIRFLOW_HOME}/airflow.cfg}"

airflow::resolve_dags_folder() {
  local candidate
  local -a candidates=()

  if [[ -n "${DATALAB_AIRFLOW_DAGS_FOLDER:-}" ]]; then
    printf '%s' "$(strip_cr "${DATALAB_AIRFLOW_DAGS_FOLDER}")"
    return 0
  fi

  candidates+=(
    "${WORKSPACE}/airflow/dags"
    "${AIRFLOW_HOME}/dags"
  )

  for candidate in "${candidates[@]}"; do
    candidate="$(strip_cr "${candidate}")"
    [[ -z "${candidate}" ]] && continue
    if [[ -d "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done

  printf '%s' "${WORKSPACE}/airflow/dags"
}

airflow::ensure_config_file() {
  mkdir -p "${AIRFLOW_HOME}"

  if [[ ! -f "${AIRFLOW_CONFIG}" ]]; then
    airflow config get-value core executor >/dev/null 2>&1 || airflow version >/dev/null 2>&1 || true
  fi
}

airflow::set_config_value() {
  local section="$1" key="$2" value="$3"
  local tmp_config

  airflow::ensure_config_file
  tmp_config="$(mktemp "${AIRFLOW_HOME}/airflow.cfg.XXXXXX")"

  awk -v section="${section}" -v key="${key}" -v value="${value}" '
    BEGIN {
      in_section = 0
      section_seen = 0
      key_written = 0
    }

    /^\[.*\]$/ {
      if (in_section && !key_written) {
        print key " = " value
        key_written = 1
      }
      in_section = ($0 == "[" section "]")
      if (in_section) {
        section_seen = 1
      }
      print
      next
    }

    in_section && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") {
      print key " = " value
      key_written = 1
      next
    }

    { print }

    END {
      if (!section_seen) {
        print "[" section "]"
      }
      if (!key_written) {
        print key " = " value
      }
    }
  ' "${AIRFLOW_CONFIG}" > "${tmp_config}"

  mv "${tmp_config}" "${AIRFLOW_CONFIG}"
}

airflow::persist_runtime_config() {
  airflow::set_config_value core dags_folder "${AIRFLOW__CORE__DAGS_FOLDER}"
  airflow::set_config_value core executor "${AIRFLOW__CORE__EXECUTOR}"
  airflow::set_config_value core parallelism "${AIRFLOW__CORE__PARALLELISM}"
  airflow::set_config_value core max_active_tasks_per_dag "${AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG}"
  airflow::set_config_value core max_active_runs_per_dag "${AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG}"
  airflow::set_config_value core load_examples "${AIRFLOW__CORE__LOAD_EXAMPLES}"
  airflow::set_config_value database sql_alchemy_conn "${AIRFLOW__DATABASE__SQL_ALCHEMY_CONN}"
}

airflow::configure_runtime() {
  export AIRFLOW_HOME AIRFLOW_CONFIG
  export AIRFLOW__CORE__LOAD_EXAMPLES="${AIRFLOW__CORE__LOAD_EXAMPLES:-False}"
  export AIRFLOW__CORE__DAGS_FOLDER="$(airflow::resolve_dags_folder)"
  export AIRFLOW__CORE__PARALLELISM="${AIRFLOW__CORE__PARALLELISM:-${AIRFLOW_CORE_PARALLELISM}}"
  export AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG="${AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG:-${AIRFLOW_CORE_MAX_ACTIVE_TASKS_PER_DAG}}"
  export AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG="${AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG:-${AIRFLOW_CORE_MAX_ACTIVE_RUNS_PER_DAG}}"
  # Airflow is pinned to PostgreSQL metadata plus LocalExecutor so DAGs can
  # run in parallel without a SQLite/SequentialExecutor fallback.
  postgres::start
  export AIRFLOW__CORE__EXECUTOR="LocalExecutor"
  export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql+psycopg2://${AIRFLOW_DB_USER}:${AIRFLOW_DB_PASSWORD}@localhost:${POSTGRES_PORT:-5432}/${AIRFLOW_DB_NAME}"
  airflow::persist_runtime_config
}

airflow::resolve_project_bootstrap_script() {
  local candidate

  if [[ -n "${DATALAB_AIRFLOW_BOOTSTRAP_SCRIPT:-}" ]]; then
    candidate="$(strip_cr "${DATALAB_AIRFLOW_BOOTSTRAP_SCRIPT}")"
    [[ -f "${candidate}" ]] && printf '%s' "${candidate}"
    return 0
  fi

  return 1
}

airflow::ensure_project_metadata() {
  local bootstrap_script=""

  bootstrap_script="$(airflow::resolve_project_bootstrap_script || true)"
  if [[ -n "${bootstrap_script}" ]]; then
    echo "[*] Running project Airflow bootstrap: ${bootstrap_script}"
    bash "${bootstrap_script}"
  fi
}

airflow::ensure_dirs() {
  mkdir -p "${AIRFLOW_PID_DIR}"
}

airflow::migrate_db() {
  airflow::configure_runtime
  airflow db migrate
}

airflow::ensure_default_user() {
  if airflow users list --output json 2>/dev/null | grep -q "\"username\": \"${AIRFLOW_DEFAULT_USERNAME}\""; then
    airflow users reset-password \
      --username "${AIRFLOW_DEFAULT_USERNAME}" \
      --password "${AIRFLOW_DEFAULT_PASSWORD}" >/dev/null 2>&1 || true
  else
    echo "[*] Creating default Airflow admin user (${AIRFLOW_DEFAULT_USERNAME})."
    airflow users create \
      --username "${AIRFLOW_DEFAULT_USERNAME}" \
      --password "${AIRFLOW_DEFAULT_PASSWORD}" \
      --firstname Data \
      --lastname Lab \
      --role Admin \
      --email "${AIRFLOW_DEFAULT_EMAIL}" >/dev/null
  fi
}

airflow::pid_alive() {
  local pid_file="$1"
  [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null
}

airflow::cleanup_stale_pids() {
  if [[ -f "${AIRFLOW_WEB_PID_FILE}" ]] && ! kill -0 "$(cat "${AIRFLOW_WEB_PID_FILE}")" 2>/dev/null; then
    rm -f "${AIRFLOW_WEB_PID_FILE}"
  fi
  if [[ -f "${AIRFLOW_SCHED_PID_FILE}" ]] && ! kill -0 "$(cat "${AIRFLOW_SCHED_PID_FILE}")" 2>/dev/null; then
    rm -f "${AIRFLOW_SCHED_PID_FILE}"
  fi
}

airflow::stop_webserver_pid() {
  if [[ -f "${AIRFLOW_WEB_PID_FILE}" ]]; then
    kill "$(cat "${AIRFLOW_WEB_PID_FILE}")" 2>/dev/null || true
    rm -f "${AIRFLOW_WEB_PID_FILE}"
  fi
}

airflow::port_open() {
  local host="$1" port="$2"
  AIRFLOW_WAIT_HOST="${host}" AIRFLOW_WAIT_PORT="${port}" python3 - <<'PY'
import os, socket, sys
host = os.environ["AIRFLOW_WAIT_HOST"]
port = int(os.environ["AIRFLOW_WAIT_PORT"])
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

airflow::wait_for_port() {
  local host="$1" port="$2" deadline
  deadline=$((SECONDS + 60))
  while [[ ${SECONDS} -lt ${deadline} ]]; do
    if airflow::port_open "${host}" "${port}"; then
      return 0
    fi
    sleep 1
  done
  echo "[!] Airflow webserver did not open ${host}:${port} within 60s." >&2
  return 1
}

airflow::start_webserver() {
  if airflow::pid_alive "${AIRFLOW_WEB_PID_FILE}"; then
    if airflow::port_open localhost "${AIRFLOW_WEB_PORT}"; then
      echo "[*] Airflow webserver already running (PID $(cat "${AIRFLOW_WEB_PID_FILE}"))."
      return
    fi
    echo "[*] Airflow webserver PID present but port ${AIRFLOW_WEB_PORT} is closed; restarting..."
    airflow::stop_webserver_pid
    sleep 1
  fi

  if [[ -f "${AIRFLOW_WEB_PID_FILE}" ]]; then
    rm -f "${AIRFLOW_WEB_PID_FILE}"
  fi

  if airflow::port_open localhost "${AIRFLOW_WEB_PORT}"; then
    echo "[*] Port ${AIRFLOW_WEB_PORT} is already in use; assuming Airflow webserver is healthy."
    return
  fi

  echo "[*] Starting Airflow webserver..."
  airflow webserver --pid "${AIRFLOW_WEB_PID_FILE}" -p "${AIRFLOW_WEB_PORT}" > "${AIRFLOW_PID_DIR}/webserver.log" 2>&1 &
  if ! airflow::wait_for_port localhost "${AIRFLOW_WEB_PORT}"; then
    echo "[!] Airflow webserver failed to bind to port ${AIRFLOW_WEB_PORT}. Recent log lines:" >&2
    tail -n 40 "${AIRFLOW_PID_DIR}/webserver.log" >&2 || true
    exit 1
  fi
}

airflow::start_scheduler() {
  if airflow::pid_alive "${AIRFLOW_SCHED_PID_FILE}"; then
    echo "[*] Airflow scheduler already running (PID $(cat "${AIRFLOW_SCHED_PID_FILE}"))."
    return
  fi
  echo "[*] Starting Airflow scheduler..."
  airflow scheduler --pid "${AIRFLOW_SCHED_PID_FILE}" > "${AIRFLOW_PID_DIR}/scheduler.log" 2>&1 &
}

airflow::start() {
  airflow::configure_runtime
  airflow::ensure_dirs
  airflow::cleanup_stale_pids
  airflow::migrate_db
  airflow::ensure_project_metadata
  airflow::ensure_default_user
  airflow::start_webserver
  airflow::start_scheduler
  echo "Airflow webserver: $(common::ui_url "${AIRFLOW_WEB_PORT}" "/")"
  echo "Airflow login: username=${AIRFLOW_DEFAULT_USERNAME} password=${AIRFLOW_DEFAULT_PASSWORD}"
}

airflow::stop() {
  if [ -f "${AIRFLOW_WEB_PID_FILE}" ]; then
    kill "$(cat "${AIRFLOW_WEB_PID_FILE}")" || true
    rm -f "${AIRFLOW_WEB_PID_FILE}"
  else
    pkill -f "airflow webserver" || true
  fi

  if [ -f "${AIRFLOW_SCHED_PID_FILE}" ]; then
    kill "$(cat "${AIRFLOW_SCHED_PID_FILE}")" || true
    rm -f "${AIRFLOW_SCHED_PID_FILE}"
  else
    pkill -f "airflow scheduler" || true
  fi

  echo "Airflow services stopped."
}
