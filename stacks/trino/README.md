# Trino Stack

This stack documents the embedded Trino query engine.

## Runtime Management

- Service module: `datalabcontainer/app/tech/trino/`
- Start: `datalab_app --start-trino`
- UI helper: `ui_services`

## Endpoints

- Inside container: `http://localhost:8091/`
- Outside host: resolved through `DATALAB_HOST_PORT_MAP`

## Runtime Data

- Root: `~/runtime/trino/`

## Why This Stack Exists

- Give the platform a fast SQL query layer across the lakehouse side of the stack.
- Provide one SQL engine that Superset can use for Hudi, Iceberg, and Delta workflows.
- Make cross-format validation easier than relying only on engine-specific CLIs.

## Common Use Cases

- Query lakehouse schemas through one endpoint.
- Validate Hudi, Iceberg, and Delta registration flows.
- Back Superset SQL Lab and dashboards with one shared SQL layer.

## How To Use In Data Lab

Start Trino:

```bash
datalab_app --start-trino
```

Then use the related docs under `docs/` for registration and query flows:

- `docs/TRINO-LAKEHOUSE-REGISTRATION.md`
- `docs/HUDI-REGISTRATION.md`
- `docs/ICEBERG-REGISTRATION.md`
- `docs/DELTA-REGISTRATION.md`

## Notes

- Trino is embedded inside the single Data Lab image.
- Use the lakehouse registration docs under `docs/` for Hudi, Iceberg, and Delta query patterns.
