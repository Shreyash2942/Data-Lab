#!/usr/bin/env bash

config::auto_profile() {
  config::detect_resources
  if [[ "${CONFIG_EFFECTIVE_CPU}" -lt 6 ]] || awk "BEGIN { exit !(${CONFIG_EFFECTIVE_MEMORY_GIB} < 12) }"; then
    printf 'conservative'
    return 0
  fi
  if [[ "${CONFIG_EFFECTIVE_CPU}" -lt 12 ]] || awk "BEGIN { exit !(${CONFIG_EFFECTIVE_MEMORY_GIB} < 24) }"; then
    printf 'balanced'
    return 0
  fi
  printf 'aggressive'
}

config::prepare_bootstrap_defaults() {
  local worker_cores worker_memory_gib app_max_cores
  local hive_threads airflow_parallelism airflow_tasks airflow_runs
  local dbt_spark_threads dbt_hive_threads spark_core_limit

  config::detect_resources
  spark_core_limit="$(config::spark_worker_core_limit)"

  worker_cores=$(( CONFIG_EFFECTIVE_CPU / 5 ))
  (( worker_cores < 2 )) && worker_cores=2
  (( worker_cores > spark_core_limit )) && worker_cores="${spark_core_limit}"

  worker_memory_gib=$(python3 - <<PY
mem = float("${CONFIG_EFFECTIVE_MEMORY_GIB}")
value = int(mem // 8)
if value < 2:
    value = 2
if value > 6:
    value = 6
print(value)
PY
)

  app_max_cores=1
  hive_threads=$(( (worker_cores + 1) / 2 ))
  (( hive_threads < 2 )) && hive_threads=2
  (( hive_threads > 4 )) && hive_threads=4
  airflow_parallelism=$(( worker_cores * 2 ))
  (( airflow_parallelism < 8 )) && airflow_parallelism=8
  (( airflow_parallelism > 16 )) && airflow_parallelism=16
  airflow_tasks=$(( worker_cores + 2 ))
  (( airflow_tasks < 4 )) && airflow_tasks=4
  (( airflow_tasks > 8 )) && airflow_tasks=8
  airflow_runs=2
  dbt_spark_threads="${worker_cores}"
  (( dbt_spark_threads < 2 )) && dbt_spark_threads=2
  (( dbt_spark_threads > 4 )) && dbt_spark_threads=4
  dbt_hive_threads="${hive_threads}"

  CONFIG_RECOMMENDED_PROFILE="bootstrap-20pct"
  CONFIG_RECOMMENDED_SPARK_WORKER_CORES="${worker_cores}"
  CONFIG_RECOMMENDED_SPARK_WORKER_MEMORY="${worker_memory_gib}g"
  CONFIG_RECOMMENDED_SPARK_APP_MAX_CORES="${app_max_cores}"
  CONFIG_RECOMMENDED_SPARK_APP_SLOTS=$(( worker_cores / app_max_cores ))
  (( CONFIG_RECOMMENDED_SPARK_APP_SLOTS < 1 )) && CONFIG_RECOMMENDED_SPARK_APP_SLOTS=1
  if (( dbt_spark_threads > CONFIG_RECOMMENDED_SPARK_APP_SLOTS )); then
    dbt_spark_threads="${CONFIG_RECOMMENDED_SPARK_APP_SLOTS}"
  fi
  (( dbt_hive_threads < 1 )) && dbt_hive_threads=1
  CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL="true"
  CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL_THREAD_NUMBER="${hive_threads}"
  CONFIG_RECOMMENDED_DBT_SPARK_THREADS="${dbt_spark_threads}"
  CONFIG_RECOMMENDED_DBT_HIVE_THREADS="${dbt_hive_threads}"
  CONFIG_RECOMMENDED_AIRFLOW_PARALLELISM="${airflow_parallelism}"
  CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_TASKS_PER_DAG="${airflow_tasks}"
  CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_RUNS_PER_DAG="${airflow_runs}"

  export CONFIG_RECOMMENDED_PROFILE \
    CONFIG_RECOMMENDED_SPARK_WORKER_CORES CONFIG_RECOMMENDED_SPARK_WORKER_MEMORY \
    CONFIG_RECOMMENDED_SPARK_APP_MAX_CORES CONFIG_RECOMMENDED_SPARK_APP_SLOTS \
    CONFIG_RECOMMENDED_DBT_SPARK_THREADS CONFIG_RECOMMENDED_DBT_HIVE_THREADS \
    CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL_THREAD_NUMBER \
    CONFIG_RECOMMENDED_AIRFLOW_PARALLELISM CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_TASKS_PER_DAG \
    CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_RUNS_PER_DAG
}

config::prepare_recommendation() {
  local requested_profile="${1:-auto}"
  local resolved_profile
  local worker_cores worker_memory_gib app_max_cores
  local hive_threads airflow_parallelism airflow_tasks airflow_runs
  local dbt_spark_threads dbt_hive_threads

  config::validate_profile "${requested_profile}"
  config::detect_resources

  resolved_profile="${requested_profile}"
  if [[ "${resolved_profile}" == "auto" ]]; then
    resolved_profile="$(config::auto_profile)"
  fi

  config::load_profile_file "${resolved_profile}"

  case "${PROFILE_NAME}" in
    conservative)
      worker_cores=$(( CONFIG_EFFECTIVE_CPU / 3 ))
      (( worker_cores < 2 )) && worker_cores=2
      (( worker_cores > 6 )) && worker_cores=6
      worker_memory_gib=$(python3 - <<PY
mem = float("${CONFIG_EFFECTIVE_MEMORY_GIB}")
value = int(mem // 6)
if value < 2:
    value = 2
if value > 8:
    value = 8
print(value)
PY
)
      app_max_cores=1
      hive_threads=2
      airflow_parallelism=$(( worker_cores * 3 ))
      (( airflow_parallelism < 8 )) && airflow_parallelism=8
      (( airflow_parallelism > 16 )) && airflow_parallelism=16
      airflow_tasks=$(( worker_cores + 2 ))
      (( airflow_tasks < 4 )) && airflow_tasks=4
      (( airflow_tasks > 8 )) && airflow_tasks=8
      airflow_runs=2
      dbt_spark_threads=2
      dbt_hive_threads=2
      ;;
    aggressive)
      worker_cores=$(( (CONFIG_EFFECTIVE_CPU * 3) / 5 ))
      (( worker_cores < 2 )) && worker_cores=2
      worker_memory_gib=$(python3 - <<PY
mem = float("${CONFIG_EFFECTIVE_MEMORY_GIB}")
value = int(mem // 4)
if value < 2:
    value = 2
if value > 16:
    value = 16
print(value)
PY
)
      if (( worker_cores >= 6 )); then
        app_max_cores=2
      else
        app_max_cores=1
      fi
      hive_threads=$(( worker_cores / 2 + 1 ))
      (( hive_threads < 2 )) && hive_threads=2
      (( hive_threads > 6 )) && hive_threads=6
      airflow_parallelism=$(( worker_cores * 4 ))
      (( airflow_parallelism < 12 )) && airflow_parallelism=12
      (( airflow_parallelism > 32 )) && airflow_parallelism=32
      airflow_tasks=$(( worker_cores * 2 ))
      (( airflow_tasks < 6 )) && airflow_tasks=6
      (( airflow_tasks > 16 )) && airflow_tasks=16
      airflow_runs=$(( worker_cores / 2 + 1 ))
      (( airflow_runs < 3 )) && airflow_runs=3
      (( airflow_runs > 8 )) && airflow_runs=8
      dbt_spark_threads=$(( worker_cores / app_max_cores ))
      (( dbt_spark_threads < 2 )) && dbt_spark_threads=2
      (( dbt_spark_threads > 6 )) && dbt_spark_threads=6
      dbt_hive_threads="${hive_threads}"
      ;;
    *)
      worker_cores=$(( CONFIG_EFFECTIVE_CPU / 2 ))
      (( worker_cores < 2 )) && worker_cores=2
      (( worker_cores > 8 )) && worker_cores=8
      worker_memory_gib=$(python3 - <<PY
mem = float("${CONFIG_EFFECTIVE_MEMORY_GIB}")
value = int(mem // 4)
if value < 2:
    value = 2
if value > 12:
    value = 12
print(value)
PY
)
      if (( worker_cores >= 8 )); then
        app_max_cores=2
      else
        app_max_cores=1
      fi
      hive_threads=$(( (worker_cores + 1) / 2 ))
      (( hive_threads < 2 )) && hive_threads=2
      (( hive_threads > 4 )) && hive_threads=4
      airflow_parallelism=$(( worker_cores * 3 ))
      (( airflow_parallelism < 10 )) && airflow_parallelism=10
      (( airflow_parallelism > 24 )) && airflow_parallelism=24
      airflow_tasks=$(( (worker_cores * 3 + 1) / 2 ))
      (( airflow_tasks < 6 )) && airflow_tasks=6
      (( airflow_tasks > 12 )) && airflow_tasks=12
      airflow_runs=$(( worker_cores / 2 ))
      (( airflow_runs < 2 )) && airflow_runs=2
      (( airflow_runs > 6 )) && airflow_runs=6
      dbt_spark_threads=$(( worker_cores / app_max_cores ))
      (( dbt_spark_threads < 2 )) && dbt_spark_threads=2
      (( dbt_spark_threads > 4 )) && dbt_spark_threads=4
      dbt_hive_threads="${hive_threads}"
      ;;
  esac

  CONFIG_RECOMMENDED_PROFILE="${PROFILE_NAME}"
  CONFIG_RECOMMENDED_SPARK_WORKER_CORES="${worker_cores}"
  CONFIG_RECOMMENDED_SPARK_WORKER_MEMORY="${worker_memory_gib}g"
  CONFIG_RECOMMENDED_SPARK_APP_MAX_CORES="${app_max_cores}"
  CONFIG_RECOMMENDED_SPARK_APP_SLOTS=$(( worker_cores / app_max_cores ))
  (( CONFIG_RECOMMENDED_SPARK_APP_SLOTS < 1 )) && CONFIG_RECOMMENDED_SPARK_APP_SLOTS=1
  if (( dbt_spark_threads > CONFIG_RECOMMENDED_SPARK_APP_SLOTS )); then
    dbt_spark_threads="${CONFIG_RECOMMENDED_SPARK_APP_SLOTS}"
  fi
  (( dbt_hive_threads < 1 )) && dbt_hive_threads=1
  CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL="true"
  CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL_THREAD_NUMBER="${hive_threads}"
  CONFIG_RECOMMENDED_DBT_SPARK_THREADS="${dbt_spark_threads}"
  CONFIG_RECOMMENDED_DBT_HIVE_THREADS="${dbt_hive_threads}"
  CONFIG_RECOMMENDED_AIRFLOW_PARALLELISM="${airflow_parallelism}"
  CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_TASKS_PER_DAG="${airflow_tasks}"
  CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_RUNS_PER_DAG="${airflow_runs}"

  export CONFIG_RECOMMENDED_PROFILE \
    CONFIG_RECOMMENDED_SPARK_WORKER_CORES CONFIG_RECOMMENDED_SPARK_WORKER_MEMORY \
    CONFIG_RECOMMENDED_SPARK_APP_MAX_CORES CONFIG_RECOMMENDED_SPARK_APP_SLOTS \
    CONFIG_RECOMMENDED_DBT_SPARK_THREADS CONFIG_RECOMMENDED_DBT_HIVE_THREADS \
    CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL_THREAD_NUMBER \
    CONFIG_RECOMMENDED_AIRFLOW_PARALLELISM CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_TASKS_PER_DAG \
    CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_RUNS_PER_DAG
}

config::recommended_env_lines() {
  cat <<EOF
SPARK_WORKER_CORES=${CONFIG_RECOMMENDED_SPARK_WORKER_CORES}
SPARK_WORKER_MEMORY=${CONFIG_RECOMMENDED_SPARK_WORKER_MEMORY}
DATALAB_SPARK_APP_MAX_CORES=${CONFIG_RECOMMENDED_SPARK_APP_MAX_CORES}
DBT_SPARK_THREADS=${CONFIG_RECOMMENDED_DBT_SPARK_THREADS}
DBT_HIVE_THREADS=${CONFIG_RECOMMENDED_DBT_HIVE_THREADS}
HIVE_EXEC_PARALLEL=${CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL}
HIVE_EXEC_PARALLEL_THREAD_NUMBER=${CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL_THREAD_NUMBER}
AIRFLOW__CORE__PARALLELISM=${CONFIG_RECOMMENDED_AIRFLOW_PARALLELISM}
AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG=${CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_TASKS_PER_DAG}
AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG=${CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_RUNS_PER_DAG}
EOF
}

config::print_compute_recommendation_sections() {
  config::print_section "Concurrency Summary"
  config::print_row "Spark app slots" "${CONFIG_RECOMMENDED_SPARK_APP_SLOTS}"
  config::print_row "dbt Spark model threads" "${CONFIG_RECOMMENDED_DBT_SPARK_THREADS}"
  config::print_row "dbt Hive model threads" "${CONFIG_RECOMMENDED_DBT_HIVE_THREADS}"
  config::print_row "Hive parallel threads" "${CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL_THREAD_NUMBER}"
  config::print_row "Airflow global tasks" "${CONFIG_RECOMMENDED_AIRFLOW_PARALLELISM}"

  config::print_section "Compute Recommendation"
  echo "Spark"
  config::print_row "Worker cores" "${CONFIG_RECOMMENDED_SPARK_WORKER_CORES}"
  config::print_row "Worker memory" "${CONFIG_RECOMMENDED_SPARK_WORKER_MEMORY}"
  config::print_row "App max cores" "${CONFIG_RECOMMENDED_SPARK_APP_MAX_CORES}"
  config::print_row "Estimated app slots" "${CONFIG_RECOMMENDED_SPARK_APP_SLOTS}"

  echo
  echo "dbt"
  config::print_row "Spark threads" "${CONFIG_RECOMMENDED_DBT_SPARK_THREADS}"
  config::print_row "Hive threads" "${CONFIG_RECOMMENDED_DBT_HIVE_THREADS}"

  echo
  echo "Hive"
  config::print_row "Parallel execution" "${CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL}"
  config::print_row "Parallel threads" "${CONFIG_RECOMMENDED_HIVE_EXEC_PARALLEL_THREAD_NUMBER}"

  echo
  echo "Airflow"
  config::print_row "Global task parallelism" "${CONFIG_RECOMMENDED_AIRFLOW_PARALLELISM}"
  config::print_row "Max tasks per DAG" "${CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_TASKS_PER_DAG}"
  config::print_row "Max DAG runs" "${CONFIG_RECOMMENDED_AIRFLOW_MAX_ACTIVE_RUNS_PER_DAG}"
}

config::show_recommendation() {
  local requested_profile="${1:-auto}" requested_category="${2:-all}"
  local spark_core_limit limit_percent
  config::validate_writable_category "${requested_category}"
  if [[ "${requested_category}" == "all" ]]; then
    requested_category="compute"
  fi
  config::prepare_recommendation "${requested_profile}"
  spark_core_limit="$(config::spark_worker_core_limit)"
  limit_percent="$(config::spark_cpu_limit_percent)"
  config::print_heading "Data Lab Config :: Recommend"
  config::print_row "Category" "$(config::category_title "${requested_category}")"
  config::print_row "Profile" "${CONFIG_RECOMMENDED_PROFILE}"

  config::print_section "Resource Snapshot"
  config::print_row "Effective CPU" "${CONFIG_EFFECTIVE_CPU}"
  config::print_row "Effective memory (GiB)" "${CONFIG_EFFECTIVE_MEMORY_GIB}"
  config::print_row "Spark worker core limit" "${spark_core_limit} (${limit_percent}% of effective CPU)"

  config::print_compute_recommendation_sections

  config::print_section "Apply-Ready Overrides"
  printf '  %-36s %-16s %s\n' "Environment key" "Recommended" "Notes"
  while IFS= read -r line; do
    config::print_env_row "$(printf '%s' "${line}" | cut -d'=' -f1)" "$(printf '%s' "${line}" | cut -d'=' -f2-)" "runtime override"
  done < <(config::recommended_env_lines)

  echo
  echo "Guardrail: Spark worker cores cannot go above ${spark_core_limit} on this container."
}
