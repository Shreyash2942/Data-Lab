#!/usr/bin/env bash
set -euo pipefail

# Helper to start the data-lab container with all common service ports mapped.
# Usage:
#   ./run-default.sh            # runs as container name "datalab"
#   ./run-default.sh myname     # uses "myname" as the container name
#   ./run-default.sh myname --foo bar   # extra args passed after image name

name="datalab"
if [[ $# -gt 0 ]]; then
  name="$1"
  shift
fi

IMAGE="${IMAGE:-shreyash42/data-lab:latest}"
readonly LOCAL_IMAGE="data-lab:latest"
readonly PUBLISHED_IMAGE="shreyash42/data-lab:latest"
if [[ "${IMAGE}" != "${LOCAL_IMAGE}" && "${IMAGE}" != "${PUBLISHED_IMAGE}" ]]; then
  echo "Use only '${LOCAL_IMAGE}' or '${PUBLISHED_IMAGE}'. Image IDs, digests, and other tags are blocked." >&2
  exit 1
fi
if [[ "${IMAGE}" == "${PUBLISHED_IMAGE}" ]]; then
  echo "Pulling latest image: ${PUBLISHED_IMAGE}"
  docker pull "${PUBLISHED_IMAGE}"
else
  docker image inspect "${LOCAL_IMAGE}" >/dev/null 2>&1 || {
    echo "Local image '${LOCAL_IMAGE}' is missing. Build it first or use '${PUBLISHED_IMAGE}'." >&2
    exit 1
  }
  echo "Using local named image: ${LOCAL_IMAGE}"
fi

docker run -d --name "${name}" \
  --user root \
  --workdir / \
  --label com.docker.compose.project= \
  --label com.docker.compose.service= \
  --label com.docker.compose.oneoff= \
  -p 4040:4040 \
  -p 8080:8080 \
  -p 8088:8088 \
  -p 8181:8181 \
  -p 8090:8090 \
  -p 8091:8091 \
  -p 9002:9002 \
  -p 9004:9004 \
  -p 9005:9005 \
  -p 8083:8083 \
  -p 8084:8084 \
  -p 9090:9090 \
  -p 9092:9092 \
  -p 9870:9870 \
  -p 9083:9083 \
  -p 10000:10000 \
  -p 10001:10001 \
  -p 5432:5432 \
  -p 27017:27017 \
  -p 6379:6379 \
  -p 18080:18080 \
  "${IMAGE}" "$@"
