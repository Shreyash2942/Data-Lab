#!/usr/bin/env bash
set -euo pipefail

# Create a non-stackable container with ports and host mounts for the workspace.
# Usage: NAME=datalab IMAGE=data-lab:latest EXTRA_PORTS="-p 8081:8081" EXTRA_VOLUMES="-v /host/path:/mnt" ./run-standalone.sh

NAME="${NAME:-datalab}"
IMAGE="${IMAGE:-data-lab:latest}"
EXTRA_PORTS="${EXTRA_PORTS:-}"
EXTRA_VOLUMES="${EXTRA_VOLUMES:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DATALAB_DIR="${REPO_ROOT}/datalabcontainer"
STACKS_DIR="${REPO_ROOT}/stacks"

docker stop "${NAME}" >/dev/null 2>&1 || true
docker rm "${NAME}" >/dev/null 2>&1 || true

docker run -d --name "${NAME}" \
  --user root \
  --workdir / \
  --label com.docker.compose.project= \
  --label com.docker.compose.service= \
  --label com.docker.compose.oneoff= \
  -p 8080:8080 -p 4040:4040 -p 9090:9090 -p 18080:18080 \
  -p 9092:9092 -p 9870:9870 -p 8088:8088 -p 10000:10000 -p 10001:10001 -p 9002:9002 \
  -p 8082:8082 -p 8083:8083 -p 8084:8084 -p 8181:8181 \
  -p 5432:5432 -p 27017:27017 -p 6379:6379 \
  ${EXTRA_PORTS} \
  -v "${DATALAB_DIR}/app:/home/datalab/app" \
  -v "${STACKS_DIR}/python:/home/datalab/python" \
  -v "${STACKS_DIR}/spark:/home/datalab/spark" \
  -v "${STACKS_DIR}/airflow:/home/datalab/airflow" \
  -v "${STACKS_DIR}/dbt:/home/datalab/dbt" \
  -v "${STACKS_DIR}/terraform:/home/datalab/terraform" \
  -v "${STACKS_DIR}/scala:/home/datalab/scala" \
  -v "${STACKS_DIR}/java:/home/datalab/java" \
  -v "${STACKS_DIR}/hive:/home/datalab/hive" \
  -v "${STACKS_DIR}/hadoop:/home/datalab/hadoop" \
  -v "${STACKS_DIR}/kafka:/home/datalab/kafka" \
  -v "${STACKS_DIR}/mongodb:/home/datalab/mongodb" \
  -v "${STACKS_DIR}/postgres:/home/datalab/postgres" \
  -v "${STACKS_DIR}/redis:/home/datalab/redis" \
  -v "${STACKS_DIR}/hudi:/home/datalab/hudi" \
  -v "${STACKS_DIR}/iceberg:/home/datalab/iceberg" \
  -v "${STACKS_DIR}/delta:/home/datalab/delta" \
  -v "${DATALAB_DIR}/runtime:/home/datalab/runtime" \
  ${EXTRA_VOLUMES} \
  "${IMAGE}" \
  sleep infinity

echo "Container ${NAME} started from ${IMAGE}."
echo "Enter with: docker exec -it -w / ${NAME} bash"
