# MinIO Stack

This stack documents the embedded MinIO object storage service.

## Runtime Management

- Service module: `datalabcontainer/app/tech/minio/`
- Start: `datalab_app --start-minio`
- UI helper: `ui_services`

## Endpoints

- API inside container: `http://localhost:9004/`
- Console inside container: `http://localhost:9005/`
- Outside host: resolved through `DATALAB_HOST_PORT_MAP`

## Runtime Data

- Root: `~/runtime/minio/`

## Why This Stack Exists

- Provide S3-compatible object storage inside the same Data Lab environment.
- Support lakehouse-style storage patterns without depending on an external cloud bucket.
- Give later workflows a place for artifacts, staging data, and object-backed datasets.

## Common Use Cases

- Store lakehouse files and object-based demo assets.
- Test S3-compatible tooling locally.
- Prepare for future MLflow or artifact-storage use on top of the same platform.

## How To Use In Data Lab

Start MinIO:

```bash
datalab_app --start-minio
```

Default credentials:

```text
minioadmin / minioadmin
```

Use `ui_services` for the correct API and console URLs when host ports are remapped.

## Notes

- MinIO is used as object storage for the lakehouse side of the platform.
- It remains part of the same single runtime image.
