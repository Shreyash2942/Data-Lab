#!/usr/bin/env bash
set -euo pipefail

dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
fi

build_source_images=(
  "quay.io/debezium/connect:3.4.0.Final"
  "marquezproject/marquez:0.50.0"
  "marquezproject/marquez-web:0.50.0"
  "prom/prometheus:v3.2.1"
  "grafana/grafana:11.5.2"
  "apicurio/apicurio-registry:3.2.0"
)

container_images="$(docker ps -a --format '{{.Image}}' 2>/dev/null || true)"

for image in "${build_source_images[@]}"; do
  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    printf '[skip] %s (not present locally)\n' "${image}"
    continue
  fi

  if grep -Fxq "${image}" <<<"${container_images}"; then
    printf '[keep] %s (used by at least one container)\n' "${image}"
    continue
  fi

  if [[ "${dry_run}" -eq 1 ]]; then
    printf '[remove] %s\n' "${image}"
    continue
  fi

  docker image rm "${image}" >/dev/null
  printf '[removed] %s\n' "${image}"
done
