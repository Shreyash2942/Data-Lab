#!/usr/bin/env bash
set -euo pipefail

HS2_HOST="${HIVE_CLI_HOST:-localhost}"
HS2_PORT="${HIVE_CLI_PORT:-10001}"
HS2_HTTP_PATH="${HIVE_CLI_HTTP_PATH:-cliservice}"
HS2_AUTH="${HIVE_CLI_AUTH:-noSasl}"
HS2_DB="${HIVE_CLI_DB:-default}"
HS2_USER="${HIVE_CLI_USER:-datalab}"
HS2_PASS="${HIVE_CLI_PASS:-}"
HS2_PROMPT="${HIVE_CLI_PROMPT:-hive (!d)> }"
HIVE_RC_FILE="${HIVE_RC_FILE:-${HOME}/.hiverc}"
BEELINE_SILENT="${HIVE_CLI_SILENT:-true}"
BEELINE_VERBOSE="${HIVE_CLI_VERBOSE:-false}"

JDBC_URL="jdbc:hive2://${HS2_HOST}:${HS2_PORT}/${HS2_DB};transportMode=http;httpPath=${HS2_HTTP_PATH};auth=${HS2_AUTH}"

if ! HS2_PROBE_HOST="${HS2_HOST}" HS2_PROBE_PORT="${HS2_PORT}" python3 - <<'PY' >/dev/null 2>&1; then
import os, socket, sys
host = os.environ["HS2_PROBE_HOST"]
port = int(os.environ["HS2_PROBE_PORT"])
s = socket.socket()
s.settimeout(2)
try:
    s.connect((host, port))
except OSError:
    sys.exit(1)
else:
    s.close()
    sys.exit(0)
PY
  cat <<EOF >&2
[!] No HiveServer2 detected on ${HS2_HOST}:${HS2_PORT}.
    Launch it inside the container:
      bash ~/app/scripts/hive/hs2.sh start
EOF
  exit 1
fi

if [ ! -f "${HIVE_RC_FILE}" ]; then
  cat <<'EOF' >"${HIVE_RC_FILE}"
-- Data Lab defaults
set hive.cli.print.current.db=true;
EOF
else
  grep -q 'set hive.cli.print.current.db=true;' "${HIVE_RC_FILE}" || echo 'set hive.cli.print.current.db=true;' >> "${HIVE_RC_FILE}"
  sed -i '/hive\.cli\.print\.current\.db\.useColor/d' "${HIVE_RC_FILE}" 2>/dev/null || true
  sed -i '/hive\.root\.logger/d' "${HIVE_RC_FILE}" 2>/dev/null || true
  sed -i '/!set prompt/d' "${HIVE_RC_FILE}" 2>/dev/null || true
fi

INIT_ARGS=()
if [ -z "${HIVE_CLI_SKIP_RC:-}" ]; then
  INIT_ARGS+=(-i "${HIVE_RC_FILE}")
fi

BEELINE_OPTS=()
if [ "${BEELINE_SILENT}" = "true" ]; then
  BEELINE_OPTS+=(--silent=true)
fi
if [ "${BEELINE_VERBOSE}" = "false" ]; then
  BEELINE_OPTS+=(--verbose=false)
fi

exec beeline \
  "${INIT_ARGS[@]}" \
  "${BEELINE_OPTS[@]}" \
  --hiveconf beeline.prompt="${HS2_PROMPT}" \
  --hiveconf hive.cli.print.current.db=true \
  -u "${JDBC_URL}" -n "${HS2_USER}" -p "${HS2_PASS}" "$@"
