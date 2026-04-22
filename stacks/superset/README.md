# Superset Stack

This stack documents the embedded Apache Superset service.

## Runtime Management

- Service module: `datalabcontainer/app/tech/superset/`
- Start: `datalab_app --start-superset`
- UI helper: `ui_services`

## Endpoints

- Inside container: `http://localhost:8090/`
- Outside host: resolved through `DATALAB_HOST_PORT_MAP`

## Runtime Data

- Root: `~/runtime/superset/`

## Why This Stack Exists

- Provide a SQL and BI layer on top of the rest of the Data Lab platform.
- Let you inspect data quickly without writing a separate frontend.
- Give the container a lightweight dashboarding and SQL Lab experience.

## Common Use Cases

- Query Trino from SQL Lab.
- Build quick dashboards on lakehouse datasets.
- Validate that registered Hudi, Iceberg, or Delta datasets are queryable through Trino.

## How To Use In Data Lab

Start Superset:

```bash
datalab_app --start-superset
```

Default login:

```text
admin / admin
```

In this project, the usual workflow is to open SQL Lab and use the `Trino Lakehouse` connection.

## Notes

- Superset is included in the main image.
- In this project, lakehouse querying is typically done through the Trino-backed Superset connection.
