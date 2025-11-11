import json
import os
import time
from typing import Iterable

from confluent_kafka import Producer

BOOTSTRAP_SERVER = os.getenv("KAFKA_BOOTSTRAP", "localhost:9092")
TOPIC = os.getenv("KAFKA_TOPIC", "datalab_python_demo")


def delivery_report(err, msg):
    if err is not None:
        print(f"❌ Delivery failed for record {msg.key()}: {err}")
    else:
        print(f"✅ Record {msg.key()} successfully produced to {msg.topic()} [{msg.partition()}] at offset {msg.offset()}")


def messages() -> Iterable[dict]:
    payloads = [
        {"event": "ingest", "ts": time.time(), "value": 42},
        {"event": "transform", "ts": time.time(), "value": 84},
    ]
    for idx, payload in enumerate(payloads, start=1):
        yield idx, payload


def main():
    producer = Producer({"bootstrap.servers": BOOTSTRAP_SERVER})
    for key, payload in messages():
        producer.produce(
            TOPIC,
            key=str(key),
            value=json.dumps(payload).encode("utf-8"),
            callback=delivery_report,
        )
    producer.flush()


if __name__ == "__main__":
    main()
