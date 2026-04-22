#!/usr/bin/env bash
# Shared CLI flag normalization helpers for start/stop/restart entrypoints.

if [[ -n "${DATALAB_CLI_FLAGS_LOADED:-}" ]]; then
  return 0
fi
DATALAB_CLI_FLAGS_LOADED=1

cli::normalize_flag() {
  local raw="${1:-}"
  raw="${raw//$'\r'/}"
  [[ -n "${raw}" ]] || {
    printf ''
    return 0
  }

  # Normalize only long options. Keep menu input and other arguments unchanged.
  if [[ "${raw}" != --* ]]; then
    printf '%s' "${raw}"
    return 0
  fi

  local body="${raw#--}"
  # Accept typo-style flags like --start--mongodb by collapsing repeated dashes.
  while [[ "${body}" == *"--"* ]]; do
    body="${body//--/-}"
  done
  # Keep one canonical separator style for easier case matching.
  body="${body//_/-}"
  printf -- '--%s' "${body}"
}

