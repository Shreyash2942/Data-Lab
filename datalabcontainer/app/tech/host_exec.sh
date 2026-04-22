#!/usr/bin/env bash
# Host/container execution helpers for Data Lab app scripts.

datalab::inside_container() {
  [ -f "/.dockerenv" ] || [ -n "${INSIDE_DATALAB:-}" ]
}

datalab::compose_service_running() {
  local repo_root="$1"
  local service_name="$2"
  (
    cd "${repo_root}" &&
    docker compose ps --services --status running 2>/dev/null | tr -d '\r' | grep -Fxq "${service_name}"
  )
}

datalab::container_running() {
  local container_name="$1"
  docker ps --format '{{.Names}}' 2>/dev/null | tr -d '\r' | grep -Fxq "${container_name}"
}

datalab::ensure_inside_or_exec() {
  local repo_root="$1"
  local service_name="$2"
  local container_name="$3"
  local script_path="$4"
  shift 4

  if datalab::inside_container; then
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "Please run inside a Data Lab container or install Docker CLI." >&2
    exit 1
  fi

  if datalab::compose_service_running "${repo_root}" "${service_name}"; then
    (
      cd "${repo_root}"
      docker compose exec -e INSIDE_DATALAB=1 -e CONTAINER_NAME="${service_name}" -e SERVICE_NAME="${service_name}" "${service_name}" "${script_path}" "$@"
    )
    exit $?
  fi

  local exec_target="${container_name}"
  if ! datalab::container_running "${exec_target}" && datalab::container_running "${service_name}"; then
    exec_target="${service_name}"
  fi

  if datalab::container_running "${exec_target}"; then
    docker exec -e INSIDE_DATALAB=1 -e CONTAINER_NAME="${exec_target}" -e SERVICE_NAME="${service_name}" "${exec_target}" "${script_path}" "$@"
    exit $?
  fi

  cat >&2 <<EOF
No running Data Lab container found.
Tried compose service '${service_name}' and container names '${container_name}'/'${service_name}'.
Start one first, then retry.
EOF
  exit 1
}
