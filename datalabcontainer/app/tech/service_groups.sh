#!/usr/bin/env bash
# shellcheck disable=SC1091
set -euo pipefail

# Shared stack-level orchestration helpers.
# Requires manage modules to be sourced by caller.

groups::start_etl() {
  airflow::start
  hadoop::ensure_running
  spark::start
  hive::prepare_cli
  kafka::start
}

groups::start_databases() {
  postgres::start
  mongodb::start
  redis::start
  dbui::start
  pgadmin::start
}

groups::start_lakehouse() {
  hadoop::ensure_running
  hive::start_metastore
  minio::start
  trino::start
  superset::start
}

groups::start_full_platform() {
  groups::start_etl
  groups::start_databases
  groups::start_lakehouse
}

groups::stop_etl() {
  airflow::stop || true
  kafka::stop || true
  hive::stop || true
  spark::stop || true
  hadoop::stop || true
}

groups::stop_databases() {
  dbui::stop || true
  redis::stop || true
  mongodb::stop || true
  postgres::stop || true
  pgadmin::stop || true
}

groups::stop_lakehouse() {
  superset::stop || true
  trino::stop || true
  minio::stop || true
}

groups::stop_full_platform() {
  groups::stop_lakehouse
  groups::stop_databases
  groups::stop_etl
}

groups::_restart_component() {
  local stop_fn="$1"
  local start_fn="$2"
  "${stop_fn}" || true
  "${start_fn}"
}

groups::restart_etl() {
  groups::_restart_component airflow::stop airflow::start
  kafka::stop || true
  hive::stop || true
  spark::stop || true
  hadoop::stop || true
  hadoop::ensure_running
  spark::start
  hive::prepare_cli
  kafka::start
}

groups::restart_databases() {
  groups::_restart_component postgres::stop postgres::start
  groups::_restart_component mongodb::stop mongodb::start
  groups::_restart_component redis::stop redis::start
  dbui::stop || true
  dbui::start
  groups::_restart_component pgadmin::stop pgadmin::start
}

groups::restart_lakehouse() {
  hadoop::ensure_running
  hive::start_metastore
  groups::_restart_component minio::stop minio::start
  groups::_restart_component trino::stop trino::start
  groups::_restart_component superset::stop superset::start
}

groups::restart_full_platform() {
  groups::restart_etl
  groups::restart_databases
  groups::restart_lakehouse
}
