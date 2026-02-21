#!/usr/bin/env bash
set -euo pipefail

# Simple end-to-end Kafka check: create a fresh topic, produce a test
# message, then consume it back to prove the broker is working.

BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-localhost:9092}"
KAFKA_BIN="${KAFKA_HOME:-/opt/kafka}/bin"

# Use a unique topic per run so offsets/history do not interfere.
TS="$(date +%s)"
TOPIC="${TOPIC:-datalab_healthcheck_${TS}}"
MESSAGE="kafka-health-${TS}-$RANDOM"

echo "[1/4] Creating topic '${TOPIC}' on ${BOOTSTRAP_SERVER}..."
"${KAFKA_BIN}/kafka-topics.sh" \
  --bootstrap-server "${BOOTSTRAP_SERVER}" \
  --create --if-not-exists \
  --topic "${TOPIC}" \
  --partitions 1 \
  --replication-factor 1 >/dev/null

echo "[2/4] Producing test message: ${MESSAGE}"
printf '%s\n' "${MESSAGE}" | "${KAFKA_BIN}/kafka-console-producer.sh" \
  --bootstrap-server "${BOOTSTRAP_SERVER}" \
  --topic "${TOPIC}" >/dev/null

echo "[3/4] Consuming it back..."
consume_out="$("${KAFKA_BIN}/kafka-console-consumer.sh" \
  --bootstrap-server "${BOOTSTRAP_SERVER}" \
  --topic "${TOPIC}" \
  --from-beginning \
  --max-messages 1 \
  --timeout-ms 5000)"

if [[ "${consume_out}" != *"${MESSAGE}"* ]]; then
  echo "[!] Did not read back the expected message. Output was:"
  printf '%s\n' "${consume_out}"
  exit 1
fi

echo "[4/4] Success! Kafka produced and consumed: ${consume_out}"
echo "Kafka is working properly on ${BOOTSTRAP_SERVER}."
