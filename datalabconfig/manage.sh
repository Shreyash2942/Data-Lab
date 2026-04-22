#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/../datalabcontainer/app/tech/host_exec.sh" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
  HOST_EXEC_PATH="${SCRIPT_DIR}/../datalabcontainer/app/tech/host_exec.sh"
  APP_COMMON_PATH="${SCRIPT_DIR}/../datalabcontainer/app/tech/common.sh"
  CONTAINER_SCRIPT_PATH="/home/datalab/datalabconfig/manage.sh"
else
  REPO_ROOT="/home/datalab"
  HOST_EXEC_PATH="/home/datalab/app/tech/host_exec.sh"
  APP_COMMON_PATH="/home/datalab/app/tech/common.sh"
  CONTAINER_SCRIPT_PATH="/home/datalab/datalabconfig/manage.sh"
fi

SERVICE_NAME="${SERVICE_NAME:-data-lab}"
CONTAINER_NAME="${CONTAINER_NAME:-datalab}"

# shellcheck source=/dev/null
source "${HOST_EXEC_PATH}"
datalab::ensure_inside_or_exec "${REPO_ROOT}" "${SERVICE_NAME}" "${CONTAINER_NAME}" "${CONTAINER_SCRIPT_PATH}" "$@"

# shellcheck source=/dev/null
source "${APP_COMMON_PATH}"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/detect.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/recommend.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/show.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/apply.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/reset.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/diff.sh"

print_usage() {
  cat <<'EOF'
Data Lab Config

Usage:
  datalab_config <command> [options]

Commands:
  show [category|key]  Show current values by category (`all`, `system`, `compute`)
  detect               Show container-visible CPU and memory sizing
  recommend [profile] [category]
                       Recommend values for `compute`
  diff [profile] [category]
                       Compare defaults, current values, and a recommendation
  apply [profile] [category]
                       Write runtime overrides for `compute`
  reset [category]     Remove runtime overrides for the managed category
  categories           List supported categories
  help                 Show this help message

Examples:
  datalab_config show
  datalab_config show compute
  datalab_config detect
  datalab_config recommend
  datalab_config recommend aggressive compute
  datalab_config diff balanced compute
  datalab_config apply balanced compute
  datalab_config reset compute

Guardrails:
  Spark worker cores are capped at 60% of effective container CPU, even when
  users edit the runtime override file manually.
EOF
}

COMMAND="${1:-help}"
case "${COMMAND}" in
  help|--help|-h)
    print_usage
    ;;
  show)
    config::show_current "${2:-}"
    ;;
  detect)
    config::show_detected_resources
    ;;
  recommend)
    config::parse_profile_and_category "${2:-}" "${3:-}" "auto" "all"
    config::show_recommendation "${CONFIG_PARSED_PROFILE}" "${CONFIG_PARSED_CATEGORY}"
    ;;
  diff)
    config::parse_profile_and_category "${2:-}" "${3:-}" "auto" "all"
    config::show_diff "${CONFIG_PARSED_PROFILE}" "${CONFIG_PARSED_CATEGORY}"
    ;;
  apply)
    config::parse_profile_and_category "${2:-}" "${3:-}" "auto" "all"
    config::apply_profile "${CONFIG_PARSED_PROFILE}" "${CONFIG_PARSED_CATEGORY}"
    ;;
  reset)
    config::reset_overrides "${2:-all}"
    ;;
  categories)
    config::print_heading "Data Lab Config :: Categories"
    config::print_row "all" "summary across available categories"
    config::print_row "system" "read-only resource snapshot and runtime paths"
    config::print_row "compute" "Spark, dbt, Hive, and Airflow tuning"
    ;;
  *)
    echo "[!] Unknown command: ${COMMAND}" >&2
    print_usage >&2
    exit 2
    ;;
esac
