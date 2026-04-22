#!/usr/bin/env bash
set -euo pipefail

TOPIC="${1:-datalab_demo}"
BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-localhost:9092}"
KAFKA_BIN="${KAFKA_HOME:-/opt/kafka}/bin"

topic_has_leader() {
  "${KAFKA_BIN}/kafka-topics.sh" --bootstrap-server "${BOOTSTRAP_SERVER}" --describe --topic "${TOPIC}" 2>/dev/null \
    | grep -Eq 'Leader:[[:space:]]*[0-9]+'
}

topic_exists() {
  "${KAFKA_BIN}/kafka-topics.sh" --bootstrap-server "${BOOTSTRAP_SERVER}" --list 2>/dev/null \
    | grep -Fxq "${TOPIC}"
}

wait_for_topic_exists() {
  local i
  for i in $(seq 1 30); do
    if topic_exists; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_leader() {
  local i
  for i in $(seq 1 60); do
    if topic_has_leader; then
      return 0
    fi
    sleep 1
  done
  return 1
}

echo "[*] Ensuring topic '${TOPIC}' exists..."
"${KAFKA_BIN}/kafka-topics.sh" --bootstrap-server "${BOOTSTRAP_SERVER}" --create --if-not-exists --topic "${TOPIC}" --partitions 1 --replication-factor 1

echo "[*] Verifying topic metadata visibility..."
if ! wait_for_topic_exists; then
  echo "[!] Topic '${TOPIC}' was not visible in broker metadata after create." >&2
  "${KAFKA_BIN}/kafka-topics.sh" --bootstrap-server "${BOOTSTRAP_SERVER}" --list || true
  exit 1
fi

echo "[*] Waiting for topic leader assignment..."
if ! wait_for_leader; then
  echo "[!] Topic '${TOPIC}' has no leader. Kafka broker is unhealthy." >&2
  "${KAFKA_BIN}/kafka-topics.sh" --bootstrap-server "${BOOTSTRAP_SERVER}" --describe --topic "${TOPIC}" || true
  exit 1
fi

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

echo "[+] Kafka demo finished."
