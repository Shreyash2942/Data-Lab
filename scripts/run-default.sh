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

docker run -d --name "${name}" \
  --user root \
  --workdir / \
  --label com.docker.compose.project= \
  --label com.docker.compose.service= \
  --label com.docker.compose.oneoff= \
  -p 4040:4040 \
  -p 8080:8080 \
  -p 8088:8088 \
  -p 9002:9002 \
  -p 9090:9090 \
  -p 9092:9092 \
  -p 9870:9870 \
  -p 10000:10000 \
  -p 10001:10001 \
  -p 18080:18080 \
  data-lab:latest "$@"
