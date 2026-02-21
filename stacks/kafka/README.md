# Kafka Layer

Apache Kafka (3.7.1, Scala 2.13) runs inside the `data-lab` container alongside Zookeeper. Data/logs live under `~/runtime/kafka`, so topics and messages persist on the host.

## Quick usage

1. Start the data services:  
   ```bash
   bash ~/app/start   # choose option 4 (or run with --start-core)
   ```
   - Kafka UI: Kafdrop auto-starts with Kafka. After recreating the `data-lab` container to expose port 9000 (`docker compose up -d --force-recreate data-lab`), open http://localhost:9000.
2. Run the built-in shell demo to create a topic, publish two messages, and consume them:
   ```bash
   bash ~/kafka/demo.sh
   ```
   (Also available from the demo menu `~/app/services_demo.sh` as option 4.)
3. Try the Python producer/consumer pair (they use `confluent-kafka`):
   ```bash
   python ~/kafka/producer.py    # sends JSON payloads to datalab_python_demo
   python ~/kafka/consumer.py    # reads from the same topic
   ```
4. Use Kafka CLI tools directly, e.g.:
   ```bash
   kafka-topics.sh --bootstrap-server localhost:9092 --list
   kafka-console-producer.sh --bootstrap-server localhost:9092 --topic datalab_demo
   kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic datalab_demo --from-beginning
   ```
5. Want an interactive chat-style test? Open two terminals:
   ```bash
   bash ~/kafka/chat_demo.sh consumer   # terminal A
   bash ~/kafka/chat_demo.sh producer   # terminal B
   ```
   Every line you type in the producer window immediately appears in the consumer.
6. Stop everything with `bash ~/app/stop`.

## Resources
- Official docs: https://kafka.apache.org/documentation/
