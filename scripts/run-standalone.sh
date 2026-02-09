#!/usr/bin/env bash
set -euo pipefail

# Create a non-stackable container with ports and host mounts for the workspace.
# Usage: NAME=datalab IMAGE=data-lab:latest EXTRA_PORTS="-p 8081:8081" EXTRA_VOLUMES="-v /host/path:/mnt" ./run-standalone.sh

NAME="${NAME:-datalab}"
IMAGE="${IMAGE:-data-lab:latest}"
EXTRA_PORTS="${EXTRA_PORTS:-}"
EXTRA_VOLUMES="${EXTRA_VOLUMES:-}"

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
  ${EXTRA_PORTS} \
  -v "$PWD/app:/home/datalab/app" \
  -v "$PWD/python:/home/datalab/python" \
  -v "$PWD/spark:/home/datalab/spark" \
  -v "$PWD/airflow:/home/datalab/airflow" \
  -v "$PWD/dbt:/home/datalab/dbt" \
  -v "$PWD/terraform:/home/datalab/terraform" \
  -v "$PWD/scala:/home/datalab/scala" \
  -v "$PWD/java:/home/datalab/java" \
  -v "$PWD/hive:/home/datalab/hive" \
  -v "$PWD/hadoop:/home/datalab/hadoop" \
  -v "$PWD/kafka:/home/datalab/kafka" \
  -v "$PWD/hudi:/home/datalab/hudi" \
  -v "$PWD/iceberg:/home/datalab/iceberg" \
  -v "$PWD/delta:/home/datalab/delta" \
  -v "$PWD/runtime:/home/datalab/runtime" \
  ${EXTRA_VOLUMES} \
  "${IMAGE}" \
  sleep infinity

echo "Container ${NAME} started from ${IMAGE}."
echo "Enter with: docker exec -it -w / ${NAME} bash"
