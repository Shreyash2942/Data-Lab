#!/usr/bin/env bash

config::reset_overrides() {
  local requested_category="${1:-all}" override_file
  config::validate_writable_category "${requested_category}"
  override_file="$(config::override_file)"

  if [[ -f "${override_file}" ]]; then
    rm -f "${override_file}"
    config::print_heading "Data Lab Config :: Reset"
    config::print_row "Category reset" "$(config::category_title "${requested_category}")"
    config::print_row "Removed override file" "${override_file}"
  else
    config::print_heading "Data Lab Config :: Reset"
    config::print_row "Category reset" "$(config::category_title "${requested_category}")"
    config::print_row "Override file" "(already absent)"
  fi

  echo
  echo "Restart these services to return to repo defaults:"
  echo "  datalab_app --restart-airflow"
  echo "  datalab_app --restart-spark"
  echo "  datalab_app --restart-hive"
}
