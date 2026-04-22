#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

: "${DATALAB_SELECTED_UI_SERVICES:=}"

ui::normalize_service_key() {
  local key
  key="$(strip_cr "${1:-}")"
  key="${key,,}"
  case "${key}" in
    airflow) printf '%s' "airflow" ;;
    spark|spark-master|spark_history|spark-history) printf '%s' "spark" ;;
    hadoop|hdfs|yarn) printf '%s' "hadoop" ;;
    hive|hiveserver2|metastore) printf '%s' "hive" ;;
    kafka|kafka-ui|broker) printf '%s' "kafka" ;;
    schema-registry|schema_registry|registry) printf '%s' "schema-registry" ;;
    kafka-connect|kafka_connect|connect) printf '%s' "kafka-connect" ;;
    postgres|postgresql|pgadmin|pg-admin) printf '%s' "postgres" ;;
    mongodb|mongo|mongo-express|mongo_express) printf '%s' "mongodb" ;;
    redis|redis-commander|redis_commander) printf '%s' "redis" ;;
    minio|minio-console) printf '%s' "minio" ;;
    trino) printf '%s' "trino" ;;
    superset) printf '%s' "superset" ;;
    jupyter|jupyterlab) printf '%s' "jupyter" ;;
    great-expectations|great_expectations|gx) printf '%s' "great-expectations" ;;
    lineage|marquez) printf '%s' "lineage" ;;
    prometheus) printf '%s' "prometheus" ;;
    grafana) printf '%s' "grafana" ;;
    *) return 1 ;;
  esac
}

ui::clear_selected_services() {
  DATALAB_SELECTED_UI_SERVICES=""
}

ui::has_selected_service() {
  local target normalized existing
  target="$(ui::normalize_service_key "${1:-}" 2>/dev/null || true)"
  [[ -n "${target}" ]] || return 1

  IFS=',' read -r -a existing <<< "${DATALAB_SELECTED_UI_SERVICES}"
  for normalized in "${existing[@]}"; do
    if [[ "${normalized}" == "${target}" ]]; then
      return 0
    fi
  done
  return 1
}

ui::add_selected_services() {
  local raw normalized
  for raw in "$@"; do
    normalized="$(ui::normalize_service_key "${raw}" 2>/dev/null || true)"
    [[ -n "${normalized}" ]] || continue
    if ui::has_selected_service "${normalized}"; then
      continue
    fi
    if [[ -n "${DATALAB_SELECTED_UI_SERVICES}" ]]; then
      DATALAB_SELECTED_UI_SERVICES+=",${normalized}"
    else
      DATALAB_SELECTED_UI_SERVICES="${normalized}"
    fi
  done
}

ui::set_selected_services() {
  ui::clear_selected_services
  ui::add_selected_services "$@"
}

ui::select_etl_stack() {
  ui::set_selected_services airflow spark hadoop hive kafka schema-registry kafka-connect
}

ui::select_database_stack() {
  ui::set_selected_services postgres mongodb redis
}

ui::select_lakehouse_stack() {
  ui::set_selected_services minio trino superset hadoop hive
}

ui::select_quality_stack() {
  ui::set_selected_services great-expectations jupyter
}

ui::select_observability_stack() {
  ui::set_selected_services lineage prometheus grafana
}

ui::select_full_platform() {
  ui::set_selected_services \
    airflow spark hadoop hive kafka schema-registry kafka-connect \
    postgres mongodb redis \
    minio trino superset \
    great-expectations jupyter \
    lineage prometheus grafana
}

ui::print_row() {
  local name="$1"
  local value="$2"
  printf '%-20s %s\n' "${name}:" "${value}"
}

ui::endpoint() {
  local scheme="$1"
  local port="$2"
  printf '%s://%s:%s' "${scheme}" "${DATALAB_UI_HOST:-localhost}" "$(common::mapped_host_port "${port}")"
}

ui::show_selected_links() {
  local service
  [[ -n "${DATALAB_SELECTED_UI_SERVICES}" ]] || return 0

  echo
  echo "=== UI Links ==="

  IFS=',' read -r -a _ui_selected <<< "${DATALAB_SELECTED_UI_SERVICES}"
  for service in "${_ui_selected[@]}"; do
    case "${service}" in
      airflow)
        ui::print_row "Airflow" "$(common::ui_url "${AIRFLOW_WEB_PORT:-8080}" "/")"
        ;;
      spark)
        ui::print_row "Spark RPC" "$(ui::endpoint "spark" 7077)"
        ui::print_row "Spark Master" "$(common::ui_url "${SPARK_MASTER_UI_PORT:-9090}" "/")"
        ui::print_row "Spark History" "$(common::ui_url "${SPARK_HISTORY_PORT:-18080}" "/")"
        ui::print_row "Spark App UI" "$(common::ui_url "${SPARK_APP_UI_PORT:-4040}" "/")"
        ;;
      hadoop)
        ui::print_row "HDFS NameNode" "$(common::ui_url "${HDFS_NAMENODE_UI_PORT:-9870}" "/")"
        ui::print_row "YARN ResourceMgr" "$(common::ui_url "${YARN_RM_UI_PORT:-8088}" "/")"
        ;;
      hive)
        ui::print_row "Hive JDBC" "$(ui::endpoint "jdbc:hive2" "${HIVE_SERVER2_THRIFT_PORT:-10000}")"
        ui::print_row "HiveServer2" "$(ui::endpoint "thrift" "${HIVE_SERVER2_THRIFT_PORT:-10000}")"
        ui::print_row "Hive Metastore" "$(ui::endpoint "thrift" "${HIVE_METASTORE_PORT:-9083}")"
        ;;
      kafka)
        ui::print_row "Kafka Broker" "$(ui::endpoint "kafka" "${KAFKA_PORT:-9092}")"
        ui::print_row "Kafka UI" "$(common::ui_url "${KAFKA_UI_PORT:-9002}" "/")"
        ;;
      schema-registry)
        ui::print_row "Schema Registry" "$(common::ui_url "${SCHEMA_REGISTRY_PORT:-8085}" "/apis/registry/v3")"
        ;;
      kafka-connect)
        ui::print_row "Kafka Connect" "$(common::ui_url "${KAFKA_CONNECT_PORT:-8086}" "/connectors")"
        ;;
      postgres)
        ui::print_row "pgAdmin UI" "$(common::ui_url "${PGADMIN_PORT:-8181}" "/")"
        ;;
      mongodb)
        ui::print_row "Mongo Express" "$(common::ui_url "${MONGO_EXPRESS_PORT:-8083}" "/")"
        ;;
      redis)
        ui::print_row "Redis Commander" "$(common::ui_url "${REDIS_COMMANDER_PORT:-8084}" "/")"
        ;;
      minio)
        ui::print_row "MinIO API" "$(common::ui_url "${MINIO_API_PORT:-9004}" "/")"
        ui::print_row "MinIO Console" "$(common::ui_url "${MINIO_CONSOLE_PORT:-9005}" "/")"
        ;;
      trino)
        ui::print_row "Trino HTTP" "$(common::ui_url "${TRINO_PORT:-8091}" "/")"
        ;;
      superset)
        ui::print_row "Superset UI" "$(common::ui_url "${SUPERSET_PORT:-8090}" "/")"
        ;;
      jupyter)
        ui::print_row "JupyterLab" "$(common::ui_url "${JUPYTER_PORT:-8888}" "/lab?token=${JUPYTER_TOKEN:-datalab}")"
        ;;
      great-expectations)
        ui::print_row "GX Data Docs" "$(common::ui_url "${GX_DOCS_PORT:-8891}" "/")"
        ;;
      lineage)
        ui::print_row "Marquez API" "$(common::ui_url "${MARQUEZ_API_PORT:-5000}" "/api/v1/namespaces")"
        ui::print_row "Marquez UI" "$(common::ui_url "${MARQUEZ_WEB_PORT:-3000}" "/")"
        ;;
      prometheus)
        ui::print_row "Prometheus UI" "$(common::ui_url "${PROMETHEUS_PORT:-9095}" "/")"
        ;;
      grafana)
        ui::print_row "Grafana UI" "$(common::ui_url "${GRAFANA_PORT:-3001}" "/")"
        ;;
    esac
  done
}
