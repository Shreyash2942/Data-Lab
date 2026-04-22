# Data Lab Finalization Report

Date: 2026-03-09

## Finalized Model

- Single Superset Trino database connection (`Trino Lakehouse`)
- 2-part SQL naming for demos (`schema.table`)
- No 3-part SQL requirement for user-facing demo flow
- No separate Node/React admin UI (database-native UIs and Superset are used)
- Lakehouse assets organized under:
  - `datalabcontainer/dev/lakehouses` (config and dev wiring)
  - `stacks/lakehouse` (demo assets, SQL, Spark scripts)

## Change Groups

### 1) Lakehouse runtime and SQL flow

- Enforced one-connection + 2-part naming behavior in Trino/Superset tooling.
- Removed legacy 3-name demo indirection and old per-format Superset database entries.
- Added/updated lakehouse demo setup and catalog smoke coverage.

Primary files:

- `datalabcontainer/app/tech/trino/manage.sh`
- `datalabcontainer/app/tech/superset/manage.sh`
- `datalabcontainer/app/ui_services`
- `stacks/lakehouse/*`
- `docs/TRINO-LAKEHOUSE-REGISTRATION.md`
- `docs/ICEBERG-REGISTRATION.md`
- `docs/DELTA-REGISTRATION.md`
- `docs/HUDI-REGISTRATION.md`

### 2) Lakehouse config reorganization

- Moved lakehouse config/development assets from scattered paths to grouped paths.
- Removed old paths under `datalabcontainer/dev/*/lakehouse`.

Primary files:

- `datalabcontainer/dev/lakehouses/*`
- `datalabcontainer/dev/trino/README.md`
- `catalog/STACK_MAP.md`

### 3) MinIO reliability and port consistency

- Standardized MinIO defaults to API `9004` and Console `9005`.
- Added stale PID cleanup and HTTP health checks for true running state.
- Updated host/container mapping logic and docs to match.

Primary files:

- `datalabcontainer/app/tech/minio/manage.sh`
- `datalabcontainer/app/start`
- `datalabcontainer/app/ui_services`
- `datalabcontainer/docker-compose.yml`
- `datalabcontainer/dev/base/Dockerfile`
- `helper/scripts/copy-container.ps1`
- `helper/scripts/run-standalone.ps1`
- `helper/scripts/build-and-run.ps1`
- `README.md`

### 4) Core service stop/start hardening

- Added shared service group orchestration helpers.
- Improved Hadoop shutdown determinism and reduced noisy stop output.
- Improved Spark stop behavior (silenced non-actionable script noise + fallback cleanup).
- Removed deprecated YARN env usage that triggered warnings.

Primary files:

- `datalabcontainer/app/tech/service_groups.sh`
- `datalabcontainer/app/tech/hadoop/manage.sh`
- `datalabcontainer/app/tech/spark/manage.sh`
- `datalabcontainer/app/tech/common.sh`

### 5) NoSQL documentation and UI behavior clarity

- Clarified MongoDB and Redis as NoSQL (no SQL-style schema/table creation UI flow).
- Added practical connection guidance for existing UI tooling.

Primary files:

- `stacks/mongodb/README.md`
- `stacks/redis/README.md`
- `docs/Data-Lab-Documentation.md`
- `docs/DATALAB-APP-CLI.md`

### 6) Admin UI removal

- Removed old dbui service script.

Primary file:

- `datalabcontainer/app/tech/dbui/manage.sh` (removed)

## Validation Summary

The following validations were executed successfully in the running `datalab` container:

1. Lakehouse smoke:
   - `/home/datalab/app/start --test-lakehouse-catalogs`
   - Result: passed (iceberg, delta, hudi)
2. Full stack validation DAG:
   - `/home/datalab/app/start --validate-stack`
   - Result: passed end-to-end
3. Script integrity:
   - Bash syntax checks on updated scripts
   - Result: passed

## Operational Notes

- If a long-running container was created before MinIO moved to `9004/9005`, recreate that container so host port bindings align with the new in-container ports.
- A benign Airflow warning about optional Graphviz rendering may still appear during DAG runs; this does not block stack validation.

