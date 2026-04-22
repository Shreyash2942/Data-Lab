# Schema Registry Stack

This stack documents the embedded Apicurio Schema Registry service used by Data Lab.

## Runtime Management

- Service module: `datalabcontainer/app/tech/schema_registry/`
- Start: `datalab_app --start-schema-registry`
- UI helper: `ui_services`

## Endpoints

- Inside container: `http://localhost:8085/apis/registry/v3`
- Outside host: resolved through `DATALAB_HOST_PORT_MAP`

## Runtime Data

- Logs: `~/runtime/schema-registry/`

## Why This Stack Exists

- Keep Kafka event schemas in one place instead of hard-coding them in producers and consumers.
- Support schema evolution so CDC and streaming pipelines can change safely over time.
- Give Data Lab a contract layer for registry-aware Kafka workflows.

## Common Use Cases

- Run PostgreSQL CDC in schema-registry mode.
- Store event contracts for Kafka topics used by downstream consumers.
- Test how producer and consumer changes behave when schemas evolve.

## How To Use In Data Lab

Start the registry:

```bash
datalab_app --start-schema-registry
```

Use it with the built-in CDC flow:

```bash
CDC_SOURCE_MODE=registry datalab_app --setup-postgres-cdc
CDC_SOURCE_MODE=registry datalab_app --verify-postgres-cdc
```

Use `ui_services` to get the correct host-mapped URL when you are in a copied container.

## Notes

- This service is part of the single final image.
- It is used by Kafka Connect and CDC demos for schema-aware payloads.
