#!/usr/bin/env bash

if [[ -n "${DATALAB_CONFIG_COMMON_LOADED:-}" ]]; then
  return 0
fi
DATALAB_CONFIG_COMMON_LOADED=1

CONFIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATALABCONFIG_HOME="$(cd "${CONFIG_LIB_DIR}/.." && pwd)"

config::all_categories() {
  cat <<'EOF'
all
system
compute
EOF
}

config::writable_categories() {
  cat <<'EOF'
all
compute
EOF
}

config::compute_keys() {
  cat <<'EOF'
SPARK_WORKER_CORES
SPARK_WORKER_MEMORY
DATALAB_SPARK_APP_MAX_CORES
DBT_SPARK_THREADS
DBT_HIVE_THREADS
HIVE_EXEC_PARALLEL
HIVE_EXEC_PARALLEL_THREAD_NUMBER
AIRFLOW__CORE__PARALLELISM
AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG
AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG
EOF
}

config::managed_keys() {
  config::compute_keys
}

config::category_title() {
  case "${1:-all}" in
    all) printf 'All Categories' ;;
    system) printf 'System' ;;
    compute) printf 'Compute' ;;
    *) return 1 ;;
  esac
}

config::is_profile() {
  case "${1:-}" in
    auto|conservative|balanced|aggressive) return 0 ;;
    *) return 1 ;;
  esac
}

config::is_category() {
  case "${1:-}" in
    all|system|compute) return 0 ;;
    *) return 1 ;;
  esac
}

config::is_writable_category() {
  case "${1:-}" in
    all|compute) return 0 ;;
    *) return 1 ;;
  esac
}

config::validate_category() {
  local category="${1:-all}"
  if config::is_category "${category}"; then
    return 0
  fi
  echo "[!] Unknown category: ${category}" >&2
  return 1
}

config::validate_writable_category() {
  local category="${1:-all}"
  if config::is_writable_category "${category}"; then
    return 0
  fi
  echo "[!] Category '${category}' is read-only or not supported for this command." >&2
  return 1
}

config::parse_profile_and_category() {
  local arg1="${1:-}" arg2="${2:-}" default_profile="${3:-auto}" default_category="${4:-all}" arg=""
  CONFIG_PARSED_PROFILE="${default_profile}"
  CONFIG_PARSED_CATEGORY="${default_category}"

  for arg in "${arg1}" "${arg2}"; do
    [[ -z "${arg}" ]] && continue
    if config::is_profile "${arg}"; then
      CONFIG_PARSED_PROFILE="${arg}"
    elif config::is_category "${arg}"; then
      CONFIG_PARSED_CATEGORY="${arg}"
    else
      echo "[!] Unknown profile/category value: ${arg}" >&2
      return 1
    fi
  done

  export CONFIG_PARSED_PROFILE CONFIG_PARSED_CATEGORY
}

config::category_keys() {
  case "${1:-all}" in
    all|compute)
      config::compute_keys
      ;;
    system)
      return 0
      ;;
    *)
      echo "[!] Unknown category: ${1:-}" >&2
      return 1
      ;;
  esac
}

config::key_label() {
  case "${1:-}" in
    SPARK_WORKER_CORES) printf 'Worker cores' ;;
    SPARK_WORKER_MEMORY) printf 'Worker memory' ;;
    DATALAB_SPARK_APP_MAX_CORES) printf 'App max cores' ;;
    DBT_SPARK_THREADS) printf 'dbt Spark threads' ;;
    DBT_HIVE_THREADS) printf 'dbt Hive threads' ;;
    HIVE_EXEC_PARALLEL) printf 'Parallel execution' ;;
    HIVE_EXEC_PARALLEL_THREAD_NUMBER) printf 'Parallel threads' ;;
    AIRFLOW__CORE__PARALLELISM) printf 'Global task parallelism' ;;
    AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG) printf 'Max tasks per DAG' ;;
    AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG) printf 'Max DAG runs' ;;
    *) printf '%s' "${1:-}" ;;
  esac
}

config::key_group() {
  case "${1:-}" in
    SPARK_WORKER_CORES|SPARK_WORKER_MEMORY|DATALAB_SPARK_APP_MAX_CORES) printf 'spark' ;;
    DBT_SPARK_THREADS|DBT_HIVE_THREADS) printf 'dbt' ;;
    HIVE_EXEC_PARALLEL|HIVE_EXEC_PARALLEL_THREAD_NUMBER) printf 'hive' ;;
    AIRFLOW__CORE__PARALLELISM|AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG|AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG) printf 'airflow' ;;
    *) printf 'other' ;;
  esac
}

config::group_title() {
  case "${1:-}" in
    spark) printf 'Spark' ;;
    dbt) printf 'dbt' ;;
    hive) printf 'Hive' ;;
    airflow) printf 'Airflow' ;;
    *) printf 'Other' ;;
  esac
}

config::default_value() {
  case "${1:-}" in
    SPARK_WORKER_CORES) printf '2' ;;
    SPARK_WORKER_MEMORY) printf '2g' ;;
    DATALAB_SPARK_APP_MAX_CORES) printf '1' ;;
    DBT_SPARK_THREADS) printf '2' ;;
    DBT_HIVE_THREADS) printf '2' ;;
    HIVE_EXEC_PARALLEL) printf 'true' ;;
    HIVE_EXEC_PARALLEL_THREAD_NUMBER) printf '2' ;;
    AIRFLOW__CORE__PARALLELISM) printf '16' ;;
    AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG) printf '8' ;;
    AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG) printf '4' ;;
    *) return 1 ;;
  esac
}

config::current_value() {
  local key="$1"
  local value="${!key:-}"
  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
    return 0
  fi
  config::default_value "${key}"
}

config::profile_file() {
  local profile="${1:-}"
  printf '%s/profiles/%s.env' "${DATALABCONFIG_HOME}" "${profile}"
}

config::validate_profile() {
  local profile="${1:-auto}"
  case "${profile}" in
    auto|conservative|balanced|aggressive)
      return 0
      ;;
    *)
      echo "[!] Unknown profile: ${profile}" >&2
      return 1
      ;;
  esac
}

config::load_profile_file() {
  local profile="$1"
  local profile_file
  profile_file="$(config::profile_file "${profile}")"
  if [[ ! -f "${profile_file}" ]]; then
    echo "[!] Missing profile file: ${profile_file}" >&2
    return 1
  fi
  unset PROFILE_NAME
  # shellcheck source=/dev/null
  source "${profile_file}"
}

config::override_file() {
  printf '%s' "${DATALAB_RUNTIME_OVERRIDE_FILE:-${RUNTIME_ROOT}/config/datalab-overrides.env}"
}

config::print_heading() {
  echo "=== $1 ==="
}

config::print_section() {
  echo
  echo "$1"
  echo "$(printf '%*s' "${#1}" '' | tr ' ' '-')"
}

config::print_row() {
  printf '  %-36s %s\n' "$1" "$2"
}

config::print_env_row() {
  printf '  %-36s %-16s %s\n' "$1" "$2" "$3"
}

config::spark_cpu_limit_percent() {
  printf '%s' "${DATALAB_SPARK_CPU_LIMIT_PERCENT:-60}"
}

config::spark_worker_core_limit() {
  local effective_cpu limit_percent core_limit
  config::detect_resources
  effective_cpu="${CONFIG_EFFECTIVE_CPU}"
  limit_percent="$(config::spark_cpu_limit_percent)"
  core_limit=$(( (effective_cpu * limit_percent) / 100 ))
  if [[ "${core_limit}" -lt 1 ]]; then
    core_limit=1
  fi
  printf '%s' "${core_limit}"
}

config::current_spark_app_slots() {
  local worker_cores app_max_cores slots
  worker_cores="$(config::current_value "SPARK_WORKER_CORES")"
  app_max_cores="$(config::current_value "DATALAB_SPARK_APP_MAX_CORES")"
  if [[ ! "${worker_cores}" =~ ^[0-9]+$ ]] || [[ "${worker_cores}" -lt 1 ]]; then
    worker_cores=1
  fi
  if [[ ! "${app_max_cores}" =~ ^[0-9]+$ ]] || [[ "${app_max_cores}" -lt 1 ]]; then
    app_max_cores=1
  fi
  slots=$(( worker_cores / app_max_cores ))
  (( slots < 1 )) && slots=1
  printf '%s' "${slots}"
}

config::recommended_value_for_key() {
  case "${1:-}" in
    SPARK_WORKER_CORES) printf '%s' "${CONFIG_RECOMMENDED_SPARK_WORKER_CORES}" ;;
    SPARK_WORKER_MEMORY) printf '%s' "${CONFIG_RECOMMENDED_SPARK_WORKER_MEMORY}" ;;
    DATALAB_SPARK_APP_MAX_CORES) printf '%s' "${CONFIG_RECOMMENDED_SPARK_APP_MAX_CORES}" ;;
    DBT_SPARK_THREADS) printf '%s' "${CONFIG_RECOMMENDED_DBT_SPARK_THREADS}" ;;
    DBT_HIVE_THREADS) printf '%s' "${CONFIG_RECOMMENDED_DBT_HIVE_THREADS}" ;;
    HIVE_EXEC_PARALLEL) printf '%s' "${CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL}" ;;
    HIVE_EXEC_PARALLEL_THREAD_NUMBER) printf '%s' "${CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL_THREAD_NUMBER}" ;;
    AIRFLOW__CORE__PARALLELISM) printf '%s' "${CONFIG_RECOMMENDED_AIRFLOW_PARALLELISM}" ;;
    AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG) printf '%s' "${CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_TASKS_PER_DAG}" ;;
    AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG) printf '%s' "${CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_RUNS_PER_DAG}" ;;
    *) return 1 ;;
  esac
}
