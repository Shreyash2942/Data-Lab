#!/usr/bin/env bash
set -euo pipefail

# Simple end-to-end Kafka check: create a fresh topic, produce a test
# message, then consume it back to prove the broker is working.

BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-localhost:9092}"
KAFKA_BIN="${KAFKA_HOME:-/opt/kafka}/bin"
RUNTIME_ROOT="${RUNTIME_ROOT:-/home/datalab/runtime}"
KAFKA_LOG_FILE="${RUNTIME_ROOT}/kafka/logs/kafka.log"
ZK_LOG_FILE="${RUNTIME_ROOT}/kafka/logs/zookeeper.log"

# Use a unique topic per run so offsets/history do not interfere.
TS="$(date +%s)"
TOPIC="${TOPIC:-datalab_healthcheck_${TS}}"
MESSAGE="kafka-health-${TS}-$RANDOM"

command -v "${KAFKA_BIN}/kafka-topics.sh" >/dev/null
command -v "${KAFKA_BIN}/kafka-console-producer.sh" >/dev/null
command -v "${KAFKA_BIN}/kafka-console-consumer.sh" >/dev/null

retry() {
  local attempts="$1"
  local sleep_seconds="$2"
  shift 2
  local i=1
  while [[ "${i}" -le "${attempts}" ]]; do
    if "$@"; then
      return 0
    fi
    if [[ "${i}" -lt "${attempts}" ]]; then
      sleep "${sleep_seconds}"
    fi
    i=$((i + 1))
  done
  return 1
}

wait_for_broker() {
  "${KAFKA_BIN}/kafka-topics.sh" --bootstrap-server "${BOOTSTRAP_SERVER}" --list >/dev/null 2>&1
}

topic_ready() {
  "${KAFKA_BIN}/kafka-topics.sh" --bootstrap-server "${BOOTSTRAP_SERVER}" --describe --topic "${TOPIC}" 2>/dev/null \
    | grep -Eq 'Leader:[[:space:]]*[0-9]+'
}

produce_message() {
  printf '%s\n' "${MESSAGE}" | "${KAFKA_BIN}/kafka-console-producer.sh" \
    --bootstrap-server "${BOOTSTRAP_SERVER}" \
    --topic "${TOPIC}" >/dev/null 2>&1
}

consume_message() {
  local out
  out="$("${KAFKA_BIN}/kafka-console-consumer.sh" \
    --bootstrap-server "${BOOTSTRAP_SERVER}" \
    --topic "${TOPIC}" \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 10000 2>/dev/null || true)"
  if [[ "${out}" == *"${MESSAGE}"* ]]; then
    printf '%s' "${out}"
    return 0
  fi
  return 1
}

print_diagnostics() {
  echo "[diag] bootstrap=${BOOTSTRAP_SERVER}"
  "${KAFKA_BIN}/kafka-topics.sh" --bootstrap-server "${BOOTSTRAP_SERVER}" --list 2>/dev/null | sed 's/^/[diag] topic: /' || true
  "${KAFKA_BIN}/kafka-topics.sh" --bootstrap-server "${BOOTSTRAP_SERVER}" --describe --topic "${TOPIC}" 2>/dev/null \
    | sed 's/^/[diag] describe: /' || true
  if [[ -f "${KAFKA_LOG_FILE}" ]]; then
    tail -n 60 "${KAFKA_LOG_FILE}" | sed 's/^/[diag] kafka.log: /' || true
  fi
  if [[ -f "${ZK_LOG_FILE}" ]]; then
    tail -n 40 "${ZK_LOG_FILE}" | sed 's/^/[diag] zookeeper.log: /' || true
  fi
}

echo "[0/4] Waiting for Kafka broker on ${BOOTSTRAP_SERVER}..."
if ! retry 60 2 wait_for_broker; then
  echo "[!] Broker not reachable in time."
  print_diagnostics
  exit 1
fi

echo "[1/4] Creating topic '${TOPIC}' on ${BOOTSTRAP_SERVER}..."
if ! retry 5 2 "${KAFKA_BIN}/kafka-topics.sh" \
  --bootstrap-server "${BOOTSTRAP_SERVER}" \
  --create --if-not-exists \
  --topic "${TOPIC}" \
  --partitions 1 \
  --replication-factor 1 >/dev/null; then
  echo "[!] Failed to create topic '${TOPIC}'."
  print_diagnostics
  exit 1
fi

if ! retry 20 1 topic_ready; then
  echo "[!] Topic '${TOPIC}' did not become ready."
  print_diagnostics
  exit 1
fi

echo "[2/4] Producing test message: ${MESSAGE}"
if ! retry 5 2 produce_message; then
  echo "[!] Failed to produce test message."
  print_diagnostics
  exit 1
fi

echo "[3/4] Consuming it back..."
consume_out=""
if ! consume_out="$(retry 5 2 consume_message)"; then
  echo "[!] Did not read back expected message '${MESSAGE}'."
  print_diagnostics
  exit 1
fi

if [[ "${consume_out}" != *"${MESSAGE}"* ]]; then
  echo "[!] Did not read back the expected message. Output was:"
  printf '%s\n' "${consume_out}"
  print_diagnostics
  exit 1
fi

echo "[4/4] Success! Kafka produced and consumed: ${consume_out}"
echo "Kafka is working properly on ${BOOTSTRAP_SERVER}."
