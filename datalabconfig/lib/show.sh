#!/usr/bin/env bash

config::show_single_key() {
  local requested_key="$1"
  local value
  config::print_heading "Data Lab Config :: Show"
  config::print_row "Setting" "${requested_key}"
  config::print_row "Label" "$(config::key_label "${requested_key}")"
  config::print_row "Current value" "$(config::current_value "${requested_key}")"
  config::print_row "Default value" "$(config::default_value "${requested_key}")"
}

config::print_compute_current_sections() {
  config::print_section "Concurrency Summary"
  config::print_row "Spark app slots" "$(config::current_spark_app_slots)"
  config::print_row "dbt Spark model threads" "$(config::current_value "DBT_SPARK_THREADS")"
  config::print_row "dbt Hive model threads" "$(config::current_value "DBT_HIVE_THREADS")"
  config::print_row "Hive parallel threads" "$(config::current_value "HIVE_EXEC_PARALLEL_THREAD_NUMBER")"
  config::print_row "Airflow global tasks" "$(config::current_value "AIRFLOW__CORE__PARALLELISM")"

  config::print_section "Compute Tuning"
  echo "Spark"
  config::print_row "Worker cores" "$(config::current_value "SPARK_WORKER_CORES")"
  config::print_row "Worker memory" "$(config::current_value "SPARK_WORKER_MEMORY")"
  config::print_row "App max cores" "$(config::current_value "DATALAB_SPARK_APP_MAX_CORES")"
  config::print_row "Estimated app slots" "$(config::current_spark_app_slots)"

  echo
  echo "dbt"
  config::print_row "Spark threads" "$(config::current_value "DBT_SPARK_THREADS")"
  config::print_row "Hive threads" "$(config::current_value "DBT_HIVE_THREADS")"

  echo
  echo "Hive"
  config::print_row "Parallel execution" "$(config::current_value "HIVE_EXEC_PARALLEL")"
  config::print_row "Parallel threads" "$(config::current_value "HIVE_EXEC_PARALLEL_THREAD_NUMBER")"

  echo
  echo "Airflow"
  config::print_row "Global task parallelism" "$(config::current_value "AIRFLOW__CORE__PARALLELISM")"
  config::print_row "Max tasks per DAG" "$(config::current_value "AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG")"
  config::print_row "Max DAG runs" "$(config::current_value "AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG")"
}

config::show_current() {
  local requested_target="${1:-all}"
  local spark_core_limit limit_percent

  if config::default_value "${requested_target}" >/dev/null 2>&1; then
    config::show_single_key "${requested_target}"
    return 0
  fi

  config::validate_category "${requested_target}"
  config::detect_resources

  config::print_heading "Data Lab Config :: Show"
  config::print_row "Category" "$(config::category_title "${requested_target}")"
  config::print_row "Override file" "$(config::override_file)"
  spark_core_limit="$(config::spark_worker_core_limit)"
  limit_percent="$(config::spark_cpu_limit_percent)"

  config::print_section "Resource Snapshot"
  config::print_row "Host logical CPU" "${CONFIG_HOST_CPU}"
  config::print_row "Host memory (GiB)" "${CONFIG_HOST_MEMORY_GIB}"
  config::print_row "Effective CPU" "${CONFIG_EFFECTIVE_CPU}"
  config::print_row "Effective memory (GiB)" "${CONFIG_EFFECTIVE_MEMORY_GIB}"
  config::print_row "Detection source" "${CONFIG_DETECTION_SOURCE}"

  config::print_section "Guardrails"
  config::print_row "Spark worker core limit" "${spark_core_limit} (${limit_percent}% of effective CPU)"

  if [[ "${requested_target}" == "all" || "${requested_target}" == "compute" ]]; then
    config::print_compute_current_sections
  fi

  if [[ "${requested_target}" == "all" || "${requested_target}" == "system" ]]; then
    config::print_section "Runtime Paths"
    config::print_row "Workspace" "${WORKSPACE}"
    config::print_row "Runtime root" "${RUNTIME_ROOT}"
    config::print_row "Override file" "$(config::override_file)"
  fi
}
