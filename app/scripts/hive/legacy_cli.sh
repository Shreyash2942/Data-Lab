#!/usr/bin/env bash
set -euo pipefail

HIVE_BIN=${HIVE_BIN:-/opt/hive/bin/hive}
HADOOP_BIN=${HADOOP_BIN:-/opt/hadoop/bin/hdfs}

HS2_HOST="${HIVE_CLI_HOST:-localhost}"
HS2_PORT="${HIVE_CLI_PORT:-10001}"
HS2_HTTP_PATH="${HIVE_CLI_HTTP_PATH:-cliservice}"
HS2_AUTH="${HIVE_CLI_AUTH:-noSasl}"
HS2_DB="${HIVE_CLI_DB:-default}"
HS2_USER="${HIVE_CLI_USER:-datalab}"
HS2_PASS="${HIVE_CLI_PASS:-}"
HS2_PROMPT="${HIVE_CLI_PROMPT:-hive (!d)> }"
HIVE_RC_FILE="${HIVE_RC_FILE:-${HOME}/.hiverc}"

JDBC_URL="jdbc:hive2://${HS2_HOST}:${HS2_PORT}/${HS2_DB};transportMode=http;httpPath=${HS2_HTTP_PATH};auth=${HS2_AUTH}"

if ! command -v "${HIVE_BIN}" >/dev/null 2>&1; then
  echo "[!] Hive binary not found at ${HIVE_BIN}." >&2
  exit 1
fi

if ! command -v "${HADOOP_BIN}" >/dev/null 2>&1; then
  echo "[!] Hadoop binary not found at ${HADOOP_BIN}." >&2
  exit 1
fi

if ! "${HADOOP_BIN}" dfsadmin -safemode get >/dev/null 2>&1; then
  cat <<'EOF' >&2
[!] Hadoop does not appear to be running.
    Run 'bash ~/app/services_start.sh' and pick option 3 first.
EOF
  exit 1
fi

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
    Launch it first: bash ~/app/scripts/hive/hs2.sh start
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
  sed -i '/!set prompt/d' "${HIVE_RC_FILE}" 2>/dev/null || true
fi

INIT_ARGS=()
if [ -z "${HIVE_CLI_SKIP_RC:-}" ]; then
  INIT_ARGS+=(-i "${HIVE_RC_FILE}")
fi

echo "[*] Launching Hive CLI session (auto-connects to ${JDBC_URL})."
exec "${HIVE_BIN}" --service cli \
  "${INIT_ARGS[@]}" \
  --hiveconf hive.cli.print.current.db=true \
  --hiveconf beeline.prompt="${HS2_PROMPT}" \
  -u "${JDBC_URL}" -n "${HS2_USER}" -p "${HS2_PASS}" "$@"
