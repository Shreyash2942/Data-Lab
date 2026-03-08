# Trino (Lakehouse)

This folder stores Trino configuration for the embedded Trino service inside the main `data-lab` container.

- Trino config template path: `datalabcontainer/dev/trino/lakehouse/etc`
- Runtime config location in container: `/home/datalab/runtime/trino/etc`
- Reference Dockerfile: `datalabcontainer/dev/trino/Dockerfile` (reference only)
- Main runtime build Dockerfile: `datalabcontainer/dev/base/Dockerfile`

Start from inside container:
- `datalab_app --start-trino`
- `datalab_app --start-lakehouse` (starts MinIO + Trino + Superset)
- `datalab_app --test-lakehouse` (runs Trino smoke tests for Iceberg/Delta/Hudi)

Default endpoint:
- `http://localhost:8091`

SQL smoke test assets:
- `datalabcontainer/dev/trino/lakehouse/tests/01-iceberg-smoke.sql`
- `datalabcontainer/dev/trino/lakehouse/tests/02-delta-smoke.sql`
- `datalabcontainer/dev/trino/lakehouse/tests/03-hudi-smoke.sql`
