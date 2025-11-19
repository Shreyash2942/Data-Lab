#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:-}"
TOPIC="${TOPIC:-datalab_chat}"
BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-localhost:9092}"
KAFKA_BIN="${KAFKA_HOME:-/opt/kafka}/bin"

usage() {
  cat <<EOF
Usage: $0 {producer|consumer} [topic]

Example workflow (two terminals):
  1) bash ~/kafka/chat_demo.sh consumer   # tail messages
  2) bash ~/kafka/chat_demo.sh producer   # type messages, hit Enter
EOF
}

if [[ "${ROLE}" != "producer" && "${ROLE}" != "consumer" ]]; then
  usage >&2
  exit 1
fi

if [[ $# -ge 2 ]]; then
  TOPIC="$2"
fi

echo "[*] Ensuring topic '${TOPIC}' exists on ${BOOTSTRAP_SERVER}..."
"${KAFKA_BIN}/kafka-topics.sh" \
  --bootstrap-server "${BOOTSTRAP_SERVER}" \
  --create --if-not-exists \
  --topic "${TOPIC}" \
  --partitions 1 \
  --replication-factor 1 >/dev/null || true

if [[ "${ROLE}" == "producer" ]]; then
  cat <<EOF
[+] Producer ready. Type messages and press Enter to send.
(Ctrl+C to exit.)
EOF
  exec "${KAFKA_BIN}/kafka-console-producer.sh" \
    --bootstrap-server "${BOOTSTRAP_SERVER}" \
    --topic "${TOPIC}"
else
  cat <<EOF
[+] Consumer ready. Waiting for messages on '${TOPIC}'.
(Ctrl+C to exit.)
EOF
  exec "${KAFKA_BIN}/kafka-console-consumer.sh" \
    --bootstrap-server "${BOOTSTRAP_SERVER}" \
    --topic "${TOPIC}" \
    --group "datalab-chat-${USER:-datalab}" \
    --from-beginning
fi
