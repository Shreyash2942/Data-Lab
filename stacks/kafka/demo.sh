#!/usr/bin/env bash
set -euo pipefail

TOPIC="${1:-datalab_demo}"
BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-localhost:9092}"
KAFKA_BIN="${KAFKA_HOME:-/opt/kafka}/bin"

echo "[*] Ensuring topic '${TOPIC}' exists..."
"${KAFKA_BIN}/kafka-topics.sh" --bootstrap-server "${BOOTSTRAP_SERVER}" --create --if-not-exists --topic "${TOPIC}" --partitions 1 --replication-factor 1

echo "[*] Producing two demo messages..."
printf "1,Hello from Kafka demo\n2,Data Lab monolithic stack\n" | "${KAFKA_BIN}/kafka-console-producer.sh" \
  --bootstrap-server "${BOOTSTRAP_SERVER}" \
  --topic "${TOPIC}" \
  --property parse.key=true \
  --property key.separator=,

echo "[*] Consuming the messages (from beginning)..."
"${KAFKA_BIN}/kafka-console-consumer.sh" \
  --bootstrap-server "${BOOTSTRAP_SERVER}" \
  --topic "${TOPIC}" \
  --from-beginning \
  --max-messages 2

echo "バ. Kafka demo finished."
