#!/usr/bin/env bash
set -euo pipefail

# Create a non-stackable container with ports and host mounts for the workspace.
# Usage: NAME=datalab IMAGE=shreyash42/data-lab:latest EXTRA_PORTS="-p 8081:8081" EXTRA_VOLUMES="-v /host/path:/mnt" ./run-standalone.sh

NAME="${NAME:-datalab}"
IMAGE="${IMAGE:-shreyash42/data-lab:latest}"
EXTRA_PORTS="${EXTRA_PORTS:-}"
EXTRA_VOLUMES="${EXTRA_VOLUMES:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DATALAB_DIR="${REPO_ROOT}/datalabcontainer"
STACKS_DIR="${REPO_ROOT}/stacks"

readonly FIXED_IMAGE="shreyash42/data-lab:latest"
if [[ "${IMAGE}" != "${FIXED_IMAGE}" ]]; then
  echo "This script is locked to image '${FIXED_IMAGE}'. Remove custom image/tag overrides." >&2
  exit 1
fi
echo "Pulling latest image: ${FIXED_IMAGE}"
docker pull "${FIXED_IMAGE}"

docker stop "${NAME}" >/dev/null 2>&1 || true
docker rm "${NAME}" >/dev/null 2>&1 || true

HOST_PORT_MAP="8080=8080,4040=4040,9090=9090,18080=18080,9092=9092,9870=9870,8088=8088,9083=9083,10000=10000,10001=10001,9002=9002,8181=8181,8083=8083,8084=8084,8085=8085,8086=8086,8888=8888,8891=8891,5000=5000,3000=3000,9095=9095,3001=3001,5432=5432,27017=27017,6379=6379,8090=8090,8091=8091,9004=9004,9005=9005"

docker run -d --name "${NAME}" \
  --user root \
  --workdir / \
  --label com.docker.compose.project= \
  --label com.docker.compose.service= \
  --label com.docker.compose.oneoff= \
  -e CONTAINER_NAME="${NAME}" \
  -e DATALAB_UI_HOST=localhost \
  -e DATALAB_HOST_PORT_MAP="${HOST_PORT_MAP}" \
  -p 8080:8080 -p 4040:4040 -p 9090:9090 -p 18080:18080 \
  -p 9092:9092 -p 9870:9870 -p 8088:8088 -p 9083:9083 -p 10000:10000 -p 10001:10001 -p 9002:9002 \
  -p 8181:8181 -p 8083:8083 -p 8084:8084 -p 8085:8085 -p 8086:8086 \
  -p 8888:8888 -p 8891:8891 -p 5000:5000 -p 3000:3000 -p 9095:9095 -p 3001:3001 \
  -p 5432:5432 -p 27017:27017 -p 6379:6379 -p 8090:8090 -p 8091:8091 -p 9004:9004 -p 9005:9005 \
  ${EXTRA_PORTS} \
  -v "${DATALAB_DIR}/app:/home/datalab/app" \
  -v "${REPO_ROOT}/datalabconfig:/home/datalab/datalabconfig" \
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
  -v "${STACKS_DIR}/kafka_connect:/home/datalab/kafka_connect" \
  -v "${STACKS_DIR}/mongodb:/home/datalab/mongodb" \
  -v "${STACKS_DIR}/minio:/home/datalab/minio" \
  -v "${STACKS_DIR}/marquez:/home/datalab/marquez" \
  -v "${STACKS_DIR}/postgres:/home/datalab/postgres" \
  -v "${STACKS_DIR}/prometheus:/home/datalab/prometheus" \
  -v "${STACKS_DIR}/redis:/home/datalab/redis" \
  -v "${STACKS_DIR}/schema_registry:/home/datalab/schema_registry" \
  -v "${STACKS_DIR}/lakehouse:/home/datalab/lakehouse" \
  -v "${STACKS_DIR}/grafana:/home/datalab/grafana" \
  -v "${STACKS_DIR}/great_expectations:/home/datalab/great_expectations" \
  -v "${STACKS_DIR}/jupyter:/home/datalab/jupyter" \
  -v "${STACKS_DIR}/superset:/home/datalab/superset" \
  -v "${STACKS_DIR}/trino:/home/datalab/trino" \
  -v "${DATALAB_DIR}/runtime:/home/datalab/runtime" \
  ${EXTRA_VOLUMES} \
  "${IMAGE}" \
  sleep infinity

docker exec "${NAME}" bash -lc '
set -e
bootstrap_paths=(
  /home/datalab/runtime/spark/events
  /home/datalab/runtime/spark/warehouse
  /home/datalab/runtime/spark/logs
  /home/datalab/runtime/spark/pids
  /home/datalab/runtime/kafka/data
  /home/datalab/runtime/kafka/logs
  /home/datalab/runtime/kafka/pids
  /home/datalab/runtime/kafka/zookeeper-data
  /home/datalab/runtime/java
  /home/datalab/runtime/scala
)
mkdir -p "${bootstrap_paths[@]}"
touch /home/datalab/derby.log 2>/dev/null || true
for _ in $(seq 1 20); do
  id datalab >/dev/null 2>&1 && break
  sleep 1
done
if id datalab >/dev/null 2>&1; then
  chown -R datalab:datalab /home/datalab/runtime "${bootstrap_paths[@]}" /home/datalab/derby.log 2>/dev/null || true
  chmod -R u+rwX,go+rX /home/datalab/runtime "${bootstrap_paths[@]}" /home/datalab/derby.log 2>/dev/null || true
fi

for p in /home/datalab/app /home/datalab/datalabconfig; do
  [ -e "$p" ] || continue
  chown -R datalab:datalab "$p" 2>/dev/null || true
  chmod -R u+rwX,go+rX "$p" 2>/dev/null || true
done
' >/dev/null 2>&1 || true

echo "Container ${NAME} started from ${IMAGE}."
echo "Enter with: docker exec -it -w / ${NAME} bash"
