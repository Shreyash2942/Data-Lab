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
  -p 4040:4040 \
  -p 8080:8080 \
  -p 8088:8088 \
  -p 9000:9000 \
  -p 9090:9090 \
  -p 9092:9092 \
  -p 9870:9870 \
  -p 10000:10000 \
  -p 18080:18080 \
  data-lab:latest "$@"
