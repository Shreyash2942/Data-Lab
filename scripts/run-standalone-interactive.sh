#!/usr/bin/env bash
set -euo pipefail

# Interactive helper to start a standalone Data Lab container with optional extra port and mount.
echo "Standalone container setup (press Enter to accept defaults)."
DEFAULT_IMAGE="shreyash42/data-lab:latest"

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
)
for p in "${extra_ports[@]}"; do
  port_flags+=(-p "${p}")
done

volume_flags=(
  -v "$PWD/app:/home/datalab/app"
  -v "$PWD/python:/home/datalab/python"
  -v "$PWD/spark:/home/datalab/spark"
  -v "$PWD/airflow:/home/datalab/airflow"
  -v "$PWD/dbt:/home/datalab/dbt"
  -v "$PWD/terraform:/home/datalab/terraform"
  -v "$PWD/scala:/home/datalab/scala"
  -v "$PWD/java:/home/datalab/java"
  -v "$PWD/hive:/home/datalab/hive"
  -v "$PWD/hadoop:/home/datalab/hadoop"
  -v "$PWD/kafka:/home/datalab/kafka"
  -v "$PWD/hudi:/home/datalab/hudi"
  -v "$PWD/iceberg:/home/datalab/iceberg"
  -v "$PWD/delta:/home/datalab/delta"
  -v "$PWD/runtime:/home/datalab/runtime"
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
