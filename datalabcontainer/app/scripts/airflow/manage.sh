#!/usr/bin/env bash
set -euo pipefail

LEGACY_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
TARGET_FILE="${LEGACY_FILE/\/scripts\//\/tech\/}"

if [[ ! -f "${TARGET_FILE}" ]]; then
  echo "[!] Compatibility wrapper target not found: ${TARGET_FILE}" >&2
  if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return 1
  fi
  exit 1
fi

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  # shellcheck source=/dev/null
  source "${TARGET_FILE}"
else
  exec bash "${TARGET_FILE}" "$@"
fi
