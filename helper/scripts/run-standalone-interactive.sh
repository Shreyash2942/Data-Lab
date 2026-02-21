#!/usr/bin/env bash
set -euo pipefail

# Interactive helper to start a standalone Data Lab container with optional extra port and mount.
echo "Standalone container setup (press Enter to accept defaults)."
DEFAULT_IMAGE="shreyash42/data-lab:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DATALAB_DIR="${REPO_ROOT}/datalabcontainer"
STACKS_DIR="${REPO_ROOT}/stacks"

read -r -p "Container name [datalab]: " NAME
NAME=${NAME:-datalab}

IMAGE="${IMAGE:-${DEFAULT_IMAGE}}"
echo "Using image: ${IMAGE} (override by setting IMAGE=...)"

# Collect optional extra port mappings
extra_ports=()
while true; do
  read -r -p "Add extra port mapping host:container (blank to finish): " EXTRA_PORT
  [[ -z "${EXTRA_PORT}" ]] && break
  extra_ports+=("${EXTRA_PORT}")
done

# Collect optional extra bind mounts
extra_mounts=()
while true; do
  read -r -p "Host path to bind (blank to finish): " HOST_PATH
  [[ -z "${HOST_PATH}" ]] && break
  if [[ ! -e "${HOST_PATH}" ]]; then
    echo "Host path '${HOST_PATH}' does not exist." >&2
    exit 1
  fi
  read -r -p "Container path for this mount (e.g., /home/datalab/data): " CONTAINER_PATH
  if [[ -z "${CONTAINER_PATH}" ]]; then
    echo "Container path is required when a host path is provided." >&2
    exit 1
  fi
  extra_mounts+=("${HOST_PATH}:${CONTAINER_PATH}")
done

port_flags=(
  -p 8080:8080
  -p 4040:4040
  -p 9090:9090
  -p 18080:18080
  -p 9092:9092
  -p 9870:9870
  -p 8088:8088
  -p 10000:10000
  -p 10001:10001
  -p 9002:9002
  -p 8082:8082
  -p 8083:8083
  -p 8084:8084
  -p 8181:8181
  -p 5432:5432
  -p 27017:27017
  -p 6379:6379
)
for p in "${extra_ports[@]}"; do
  port_flags+=(-p "${p}")
done

volume_flags=(
  -v "${DATALAB_DIR}/app:/home/datalab/app"
  -v "${STACKS_DIR}/python:/home/datalab/python"
  -v "${STACKS_DIR}/spark:/home/datalab/spark"
  -v "${STACKS_DIR}/airflow:/home/datalab/airflow"
  -v "${STACKS_DIR}/dbt:/home/datalab/dbt"
  -v "${STACKS_DIR}/terraform:/home/datalab/terraform"
  -v "${STACKS_DIR}/scala:/home/datalab/scala"
  -v "${STACKS_DIR}/java:/home/datalab/java"
  -v "${STACKS_DIR}/hive:/home/datalab/hive"
  -v "${STACKS_DIR}/hadoop:/home/datalab/hadoop"
  -v "${STACKS_DIR}/kafka:/home/datalab/kafka"
  -v "${STACKS_DIR}/mongodb:/home/datalab/mongodb"
  -v "${STACKS_DIR}/postgres:/home/datalab/postgres"
  -v "${STACKS_DIR}/redis:/home/datalab/redis"
  -v "${STACKS_DIR}/hudi:/home/datalab/hudi"
  -v "${STACKS_DIR}/iceberg:/home/datalab/iceberg"
  -v "${STACKS_DIR}/delta:/home/datalab/delta"
  -v "${DATALAB_DIR}/runtime:/home/datalab/runtime"
)
for m in "${extra_mounts[@]}"; do
  volume_flags+=(-v "${m}")
done

docker stop "${NAME}" >/dev/null 2>&1 || true
docker rm "${NAME}" >/dev/null 2>&1 || true

docker run -d --name "${NAME}" \
  --user root \
  --workdir / \
  --label com.docker.compose.project= \
  --label com.docker.compose.service= \
  --label com.docker.compose.oneoff= \
  "${port_flags[@]}" \
  "${volume_flags[@]}" \
  "${IMAGE}" \
  sleep infinity

echo "Container ${NAME} started from ${IMAGE}."
if [[ ${#extra_ports[@]} -gt 0 ]]; then
  echo "Added port bindings: ${extra_ports[*]}"
fi
if [[ ${#extra_mounts[@]} -gt 0 ]]; then
  echo "Mounted: ${extra_mounts[*]}"
fi
echo "Enter with: docker exec -it -w / ${NAME} bash"
