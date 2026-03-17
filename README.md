# Data Lab - All-in-One Data Engineering Sandbox

Data Lab is a single-container data engineering environment for Spark, Hadoop, Hive, Kafka, Airflow, dbt, Great Expectations, JupyterLab, PostgreSQL, MongoDB, Redis, and lakehouse formats (Hudi/Iceberg/Delta).

![Data Lab Cover](docs/images/coverimage.png)

## Repository Layout
- `datalabcontainer/`: container build/runtime assets
- `stacks/`: stack examples and stack-level READMEs
- `helper/scripts/`: host-side helper scripts for build/run/copy/access
- `docs/`: architecture and detailed documentation

## Current Stack Versions
- Spark `3.5.1`
- Hadoop `3.3.6`
- Hive `2.3.9` (compatible with Spark 3.5)
- Kafka `3.7.1`
- Kafka Connect `3.7.1` (bundled with Kafka)
- Debezium PostgreSQL Connector `3.4.0.Final`
- Apicurio Registry `3.2.0`
- OpenLineage Spark integration `1.38.0`
- Marquez `0.50.0`
- Prometheus `3.2.1`
- Grafana `11.5.2`
- Great Expectations `1.15.0`
- JupyterLab `4.2.7`
- Airflow `2.9.3`
- Hudi `0.15.0`
- Iceberg `1.6.1`
- Delta Lake `3.2.0`
- Trino `435` (embedded)
- Superset `4.1.2` (embedded)
- MinIO (embedded)

## Quick Start (Compose)
```bash
cp datalabcontainer/.env.example datalabcontainer/.env
cd datalabcontainer
docker compose build
docker compose up -d
docker compose exec data-lab bash
su - datalab
```

Service control:
```bash
datalab_app
datalab_app --start-core
```

CDC demo:
```bash
datalab_app --setup-postgres-cdc
datalab_app --verify-postgres-cdc

CDC_SOURCE_MODE=registry datalab_app --setup-postgres-cdc
CDC_SOURCE_MODE=registry datalab_app --verify-postgres-cdc
```

Quality and dev tools:
```bash
datalab_app --start-quality-stack
datalab_app --run-great-expectations-demo
datalab_app --start-jupyter
datalab_app --start-great-expectations
```

Observability and lineage:
```bash
datalab_app --start-observability-stack
datalab_app --run-lineage-demo
datalab_app --start-lineage
datalab_app --start-prometheus
datalab_app --start-grafana
```

## System Requirements

Minimum (container runs, core workflows possible):

1. CPU: 4 vCPU
2. RAM: 12 GB
3. Disk: 50 GB free SSD
4. Docker: Docker Desktop or Docker Engine with Compose support

Recommended (full platform smoother: Airflow + Spark + Hive + Trino + Superset + DB UIs + JupyterLab):

1. CPU: 8 vCPU
2. RAM: 24 GB
3. Disk: 100 GB free SSD
4. Docker Desktop resource limits (if used): at least 8 CPU and 20+ GB memory

Future-oriented target (for later data engineering expansion on the same single-container topology):

1. CPU: 12 vCPU
2. RAM: 32 GB
3. Disk: 150 GB free SSD
4. Notes: suitable for adding schema registry, Kafka Connect/CDC, data quality, lineage, notebook, and monitoring services without changing the current monolithic module pattern

Future-oriented target (for later ML/AI profile work on the same topology):

1. CPU: 12+ vCPU
2. RAM: 32 to 64 GB
3. Disk: 200 GB free SSD
4. Optional GPU: NVIDIA GPU with 12+ GB VRAM (only for local LLM serving/inference)
5. Notes: AI/ML services should remain optional modules layered on top of the existing data engineering stack

## Topology and Dynamic Port Rules

The current required topology is preserved for future work:

1. Single container remains the default runtime model
2. New capabilities should be added as modular tech services under `datalabcontainer/app/tech/*`
3. Runtime state should stay under `datalabcontainer/runtime/<service>`
4. Future services must support dynamic host port mapping

Dynamic port support means:

1. Each service keeps a stable internal container port
2. Host ports may change when a copied container is created
3. Host-side URLs must be resolved through `DATALAB_HOST_PORT_MAP`
4. `ui_services` and `datalab_app` remain the source of truth for outside-host endpoints
5. Future docs and helper scripts should print both inside-container and outside-host endpoints when applicable

## Quick Start (Standalone)
Linux/macOS:
```bash
NAME=datalab IMAGE=data-lab:latest ./helper/scripts/run-standalone.sh
```

Windows PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\run-standalone.ps1 -Name datalab -Image data-lab:latest
```

## Service Endpoints
- Airflow: `http://localhost:8080/`
- Spark Master UI: `http://localhost:9090/`
- Spark History: `http://localhost:18080/`
- Spark App UI: `http://localhost:4040/`
- HDFS NameNode: `http://localhost:9870/`
- YARN ResourceManager: `http://localhost:8088/`
- HiveServer2 Thrift: `thrift://localhost:10000`
- Kafka UI: `http://localhost:9002/`
- Schema Registry API: `http://localhost:8085/apis/registry/v3`
- Kafka Connect API: `http://localhost:8086/connectors`
- JupyterLab: `http://localhost:8888/lab?token=datalab`
- Great Expectations Data Docs: `http://localhost:8891/`
- Marquez UI: `http://localhost:3000/`
- Marquez API: `http://localhost:5000/api/v1/namespaces`
- Prometheus: `http://localhost:9095/`
- Grafana: `http://localhost:3001/`
- pgAdmin: `http://localhost:8181/`
- Trino: `http://localhost:8091/`
- Superset: `http://localhost:8090/`
- MinIO API: `http://localhost:9004/`
- MinIO Console: `http://localhost:9005/`

Connection endpoints:
- Spark RPC: `spark://localhost:7077`
- Hive Metastore: `thrift://localhost:9083`
- HiveServer2 Thrift: `thrift://localhost:10000`
- Schema Registry API: `http://localhost:8085/apis/registry/v3`
- Kafka Connect API: `http://localhost:8086/connectors`
- PostgreSQL: `postgresql://localhost:5432`
- MongoDB: `mongodb://localhost:27017`
- Redis: `redis://localhost:6379`

Built-in CDC demo names:
- JSON mode: connector `datalab-postgres-cdc`, topic `datalab_cdc.public.customer_events`
- Registry mode: connector `datalab-postgres-cdc-registry`, topic `datalab_cdc-registry.public.customer_events`

Built-in Phase 3 quality/dev defaults:
- Jupyter token: `datalab`
- Jupyter starter notebook: `/home/datalab/runtime/jupyter/notebooks/DataLab_Phase3_Quickstart.ipynb`
- Great Expectations result file: `/home/datalab/runtime/great_expectations/last_validation.json`
- Great Expectations demo dataset: `/home/datalab/runtime/great_expectations/demo_data/customer_events_quality.csv`
- OpenLineage namespace: `datalab` by default (or `CONTAINER_NAME` when set)
- Marquez lineage demo paths:
  - `/home/datalab/runtime/lineage/demo/bronze`
  - `/home/datalab/runtime/lineage/demo/silver`
- Grafana default login: `admin / admin`

## Runtime Data
All mutable service state is under:
- Host: `datalabcontainer/runtime/`
- Container: `/home/datalab/runtime/`

You can reset a stack by removing only its runtime subfolder (for example `datalabcontainer/runtime/airflow`).

## Docker Optimization Notes
- `.dockerignore` excludes runtime state, helpers, docs, and local caches from build context.
- Base Dockerfile enables:
  - `PIP_NO_CACHE_DIR=1`
  - `PIP_DISABLE_PIP_VERSION_CHECK=1`
  - npm update-notifier/fund disabled
  - npm cache cleanup after global installs
- Python package installation is consolidated to reduce image layers.
- Service scripts are normalized for CRLF in entrypoint to avoid `bash\r` failures on Windows-mounted files.

## Recommended Build/Push Optimization
- Use `docker buildx` with registry cache in GitHub Actions.
- Build only on `main` (or release tags) for Docker Hub pushes.
- Use branch CI on `dev` for tests/lint only.
- Keep image tags:
  - immutable (`:sha-<commit>`)
  - rolling (`:latest`)

## Single Runtime Image Note

`data-lab:latest` is the only runtime image you need to run the platform.

The extra images you may see locally such as:

- `prom/prometheus`
- `grafana/grafana`
- `marquezproject/marquez`
- `marquezproject/marquez-web`
- `apicurio/apicurio-registry`
- `quay.io/debezium/connect`

are build-source images used by the multi-stage Dockerfile. They are not separate runtime containers for Data Lab.

After `data-lab:latest` is built, those build-source images can be removed safely if no other container is using them.

Safe cleanup helpers:

Windows PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\cleanup-build-source-images.ps1
```

Dry run:
```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\cleanup-build-source-images.ps1 -DryRun
```

Linux/macOS:
```bash
bash ./helper/scripts/cleanup-build-source-images.sh
```

Dry run:
```bash
bash ./helper/scripts/cleanup-build-source-images.sh --dry-run
```

## References
- Data Lab CLI guide: `docs/DATALAB-APP-CLI.md`
- Trino lakehouse registration guide: `docs/TRINO-LAKEHOUSE-REGISTRATION.md`
- Hudi registration guide: `docs/HUDI-REGISTRATION.md`
- Iceberg registration guide: `docs/ICEBERG-REGISTRATION.md`
- Delta registration guide: `docs/DELTA-REGISTRATION.md`
- Future data engineering expansion roadmap: `docs/DATA-ENGINEERING-EXPANSION-ROADMAP.md`
- Future ML/AI roadmap: `docs/ML-AI-FUTURE-ROADMAP.md`
- Container topology guide (single vs multi-container): `docs/CONTAINER-TOPOLOGY-GUIDE.md`
- Spark: https://spark.apache.org/docs/latest/
- Hadoop: https://hadoop.apache.org/docs/stable/
- Hive: https://cwiki.apache.org/confluence/display/Hive/Home
- Kafka: https://kafka.apache.org/documentation/
- Airflow: https://airflow.apache.org/docs/
- dbt: https://docs.getdbt.com/
- PostgreSQL: https://www.postgresql.org/docs/
- MongoDB: https://www.mongodb.com/docs/
- Redis: https://redis.io/docs/
- Hudi: https://hudi.apache.org/docs/
- Iceberg: https://iceberg.apache.org/docs/latest/
- Delta Lake: https://docs.delta.io/latest/
