#!/usr/bin/env bash
set -euo pipefail

: "${DATALAB_LOG_RETENTION_ENABLED:=1}"
: "${DATALAB_LOG_RETENTION_MAX_TOTAL_MB:=1024}"
: "${DATALAB_LOG_RETENTION_MAX_FILES:=500}"
: "${DATALAB_LOG_RETENTION_FILE_PATTERNS:=*.log *.out *.err}"

logs::to_bytes() {
  local mb="${1:-0}"
  if [[ ! "${mb}" =~ ^[0-9]+$ ]]; then
    echo 0
    return
  fi
  echo $((mb * 1024 * 1024))
}

logs::collect() {
  local pattern
  local patterns=()
  for pattern in ${DATALAB_LOG_RETENTION_FILE_PATTERNS}; do
    patterns+=(-name "${pattern}" -o)
  done
  unset 'patterns[${#patterns[@]}-1]'

  find "${RUNTIME_ROOT}" -type f \( "${patterns[@]}" \) -printf '%T@ %p\n' 2>/dev/null | sort -n
}

logs::remove_oldest() {
  local target_total_bytes
  local max_files
  target_total_bytes="$(logs::to_bytes "${DATALAB_LOG_RETENTION_MAX_TOTAL_MB}")"
  max_files="${DATALAB_LOG_RETENTION_MAX_FILES}"
  [[ "${max_files}" =~ ^[0-9]+$ ]] || max_files=0

  local total_bytes=0
  local line path size
  local -a files=()
  local -a sizes=()

  while IFS= read -r line; do
    path="${line#* }"
    [[ -f "${path}" ]] || continue
    size="$(stat -c '%s' "${path}" 2>/dev/null || echo 0)"
    files+=("${path}")
    sizes+=("${size}")
    total_bytes=$((total_bytes + size))
  done < <(logs::collect)

  local total_files=${#files[@]}
  local removed=0
  local i=0
  while (( i < total_files )); do
    local current_count
    current_count=$((total_files - removed))

    if (( max_files > 0 && current_count > max_files )); then
      :
    elif (( target_total_bytes > 0 && total_bytes > target_total_bytes )); then
      :
    else
      break
    fi

    path="${files[$i]}"
    size="${sizes[$i]}"
    if [[ -f "${path}" ]] && rm -f -- "${path}"; then
      total_bytes=$((total_bytes - size))
      removed=$((removed + 1))
    fi
    i=$((i + 1))
  done

  if (( removed > 0 )); then
    local final_count
    final_count=$((total_files - removed))
    echo "[*] Log retention removed ${removed} old file(s); current count=${final_count}, size=$((total_bytes / 1024 / 1024))MB."
  fi
}

logs::prune_if_needed() {
  if [[ "${DATALAB_LOG_RETENTION_ENABLED}" != "1" ]]; then
    return 0
  fi
  logs::remove_oldest
}
