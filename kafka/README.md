# Kafka Layer

Apache Kafka (3.7.1, Scala 2.13) runs inside the `data-lab` container alongside Zookeeper. Data/logs live under `/workspace/kafka`, so topics and messages persist on the host.

## Quick usage

1. Start the data services:  
   ```bash
   bash /workspace/app/scripts/services_start.sh   # choose option 3 (or run with --start-core)
   ```
2. Run the built-in shell demo to create a topic, publish two messages, and consume them:
   ```bash
   bash /workspace/kafka/demo.sh
   ```
   (Also available from the menu as option 7.)
3. Try the Python producer/consumer pair (they use `confluent-kafka`):
   ```bash
   python /workspace/kafka/producer.py    # sends JSON payloads to datalab_python_demo
   python /workspace/kafka/consumer.py    # reads from the same topic
   ```
4. Use Kafka CLI tools directly, e.g.:
   ```bash
   kafka-topics.sh --bootstrap-server localhost:9092 --list
   kafka-console-producer.sh --bootstrap-server localhost:9092 --topic datalab_demo
   kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic datalab_demo --from-beginning
   ```
5. Stop everything with `bash /workspace/app/scripts/services_stop.sh`.

## Resources
- Official docs: https://kafka.apache.org/documentation/
