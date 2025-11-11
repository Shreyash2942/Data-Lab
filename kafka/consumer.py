import json
import os
from confluent_kafka import Consumer, KafkaException

BOOTSTRAP_SERVER = os.getenv("KAFKA_BOOTSTRAP", "localhost:9092")
TOPIC = os.getenv("KAFKA_TOPIC", "datalab_python_demo")
GROUP_ID = os.getenv("KAFKA_GROUP_ID", "datalab-consumer")


def main():
    consumer = Consumer(
        {
            "bootstrap.servers": BOOTSTRAP_SERVER,
            "group.id": GROUP_ID,
            "auto.offset.reset": "earliest",
        }
    )
    consumer.subscribe([TOPIC])
    print(f"[*] Listening to topic '{TOPIC}' on {BOOTSTRAP_SERVER}...")

    try:
        while True:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                raise KafkaException(msg.error())
            key = msg.key().decode() if msg.key() else None
            value = json.loads(msg.value().decode())
            print(f"🗃️  key={key} payload={value}")
    except KeyboardInterrupt:
        print("Stopping consumer...")
    finally:
        consumer.close()


if __name__ == "__main__":
    main()
