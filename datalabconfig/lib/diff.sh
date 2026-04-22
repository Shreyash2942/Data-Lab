#!/usr/bin/env bash

config::show_diff() {
  local requested_profile="${1:-auto}" requested_category="${2:-all}"
  local key default_value current_value recommended_value group current_group=""

  config::validate_writable_category "${requested_category}"
  if [[ "${requested_category}" == "all" ]]; then
    requested_category="compute"
  fi
  config::prepare_recommendation "${requested_profile}"
  config::print_heading "Data Lab Config :: Diff"
  config::print_row "Category" "$(config::category_title "${requested_category}")"
  config::print_row "Recommendation profile" "${CONFIG_RECOMMENDED_PROFILE}"
  config::print_section "Compute Delta"
  printf '  %-28s %-12s %-12s %-12s\n' "Setting" "Default" "Current" "Recommended"

  while IFS= read -r key; do
    group="$(config::key_group "${key}")"
    if [[ "${group}" != "${current_group}" ]]; then
      echo
      echo "$(config::group_title "${group}")"
      current_group="${group}"
    fi
    default_value="$(config::default_value "${key}")"
    current_value="$(config::current_value "${key}")"
    recommended_value="$(config::recommended_value_for_key "${key}")"
    printf '  %-28s %-12s %-12s %-12s\n' "$(config::key_label "${key}")" "${default_value}" "${current_value}" "${recommended_value}"
  done < <(config::category_keys "${requested_category}")
}
