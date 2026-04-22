# Kafka Layer

Apache Kafka (3.7.1, Scala 2.13) runs inside the `data-lab` container alongside Zookeeper. Data/logs live under `~/runtime/kafka`, so topics and messages persist on the host.

Phase 1 data engineering additions now included in the same container:

1. Kafka Connect REST API on `http://localhost:8086/connectors`
2. Apicurio Schema Registry API on `http://localhost:8085/apis/registry/v3`
3. PostgreSQL CDC demo flow through Debezium

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

## Kafka Connect quick usage

1. Start the ETL stack or start the service directly:
   ```bash
   datalab_app --start-kafka-connect
   ```
2. Check the REST API:
   ```bash
   curl http://localhost:8086/connectors
   ```
3. Inspect available bundled connector plugins:
   ```bash
   curl http://localhost:8086/connector-plugins
   ```
4. Add external connector plugins under:
   ```bash
   ~/runtime/kafka-connect/plugins
   ```
5. After adding plugins, restart Kafka Connect and post the connector config:
   ```bash
   datalab_app --restart-kafka-connect
   curl -X POST http://localhost:8086/connectors \
     -H 'Content-Type: application/json' \
     --data @/path/to/your-connector.json
   ```

## PostgreSQL CDC demo

Validated demo modes:

1. JSON mode
   - connector: `datalab-postgres-cdc`
   - topic: `datalab_cdc.public.customer_events`
2. Schema Registry mode
   - connector: `datalab-postgres-cdc-registry`
   - topic: `datalab_cdc-registry.public.customer_events`

Run the JSON demo:

```bash
datalab_app --setup-postgres-cdc
datalab_app --verify-postgres-cdc
```

Run the Schema Registry-backed demo:

```bash
CDC_SOURCE_MODE=registry datalab_app --setup-postgres-cdc
CDC_SOURCE_MODE=registry datalab_app --verify-postgres-cdc
```

Reset the demo for the selected mode:

```bash
datalab_app --reset-postgres-cdc
# or
CDC_SOURCE_MODE=registry datalab_app --reset-postgres-cdc
```

Sample connector config files are bundled at:

```bash
~/kafka/connectors/postgres-cdc-basic.json
~/kafka/connectors/postgres-cdc-registry.json
```

In registry mode, Apicurio artifacts are auto-created for the topic key/value schemas.

## Schema Registry quick usage

1. Start the service directly:
   ```bash
   datalab_app --start-schema-registry
   ```
2. Check health:
   ```bash
   curl http://localhost:8085/apis/registry/v3/system/info
   ```
3. Check the registry API root:
   ```bash
   curl http://localhost:8085/apis/registry/v3
   ```

## Resources
- Official docs: https://kafka.apache.org/documentation/
- Kafka Connect docs: https://kafka.apache.org/documentation/#connect
- Apicurio Registry docs: https://www.apicur.io/registry/docs/apicurio-registry/3.1.x/index.html
