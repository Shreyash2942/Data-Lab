# Kafka Connect Stack

This stack documents the embedded Kafka Connect service used for connector-based ingestion.

## Runtime Management

- Service module: `datalabcontainer/app/tech/kafka_connect/`
- Start: `datalab_app --start-kafka-connect`
- UI helper: `ui_services`

## Endpoints

- Inside container: `http://localhost:8086/connectors`
- Outside host: resolved through `DATALAB_HOST_PORT_MAP`

## Related Assets

- Example connector configs: `stacks/kafka/connectors/`
- CDC helper module: `datalabcontainer/app/tech/cdc/`

## Runtime Data

- Logs/plugins: `~/runtime/kafka-connect/`

## Why This Stack Exists

- Provide standard connector-based ingestion instead of writing one-off import scripts.
- Make CDC and future source/sink integrations repeatable.
- Keep connector lifecycle management inside the same Data Lab platform.

## Common Use Cases

- Capture PostgreSQL changes with Debezium.
- Add future sink connectors for warehouse or object-storage targets.
- Inspect connector health, task state, and plugin availability.

## How To Use In Data Lab

Start Kafka Connect:

```bash
datalab_app --start-kafka-connect
```

Use the built-in PostgreSQL CDC setup:

```bash
datalab_app --setup-postgres-cdc
datalab_app --verify-postgres-cdc
```

Registry-backed mode is also available:

```bash
CDC_SOURCE_MODE=registry datalab_app --setup-postgres-cdc
```

Example connector JSON files are stored in `stacks/kafka/connectors/`.

## Notes

- Kafka Connect is bundled inside the main Data Lab image.
- PostgreSQL CDC is implemented through Debezium in this stack.
