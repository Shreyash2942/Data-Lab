# Data Lab

Data Lab is a portfolio-ready, single-container data engineering platform that brings together batch processing, streaming, lakehouse analytics, data quality, notebooks, and observability in one reproducible local environment.

![Data Lab Cover](docs/images/coverimage.png)

## Why This Project Stands Out

- One runtime, many workflows: Spark, Hadoop, Hive, Kafka, Airflow, dbt, Great Expectations, JupyterLab, Trino, Superset, MinIO, PostgreSQL, MongoDB, Redis, and observability tooling run as one coordinated platform.
- Built for real demos: the repo includes ready-to-run workflows for CDC, lakehouse querying, quality checks, and lineage exploration.
- Operationally thoughtful: service modules follow a consistent pattern, runtime state is isolated per service, and host-side URLs remain usable even when ports are remapped.

## Platform Highlights

- Batch and SQL: Spark, Hive, Trino, Superset
- Storage and lakehouse: HDFS, MinIO, Hudi, Iceberg, Delta Lake
- Streaming and CDC: Kafka, Kafka Connect, Debezium, Apicurio Registry
- Orchestration and development: Airflow, dbt, JupyterLab
- Quality and observability: Great Expectations, OpenLineage, Marquez, Prometheus, Grafana
- Supporting data services: PostgreSQL, MongoDB, Redis

## Architecture Snapshot

- Runtime model: a single container remains the default deployment shape.
- Service model: each capability lives under `datalabcontainer/app/tech/*` as a modular service script.
- State model: mutable runtime data lives under `datalabcontainer/runtime/*`.
- Access model: services keep stable internal ports while host ports can be remapped safely through `ui_services` and `datalab_app`.

## Quick Start

### Docker Compose

```bash
cp datalabcontainer/.env.example datalabcontainer/.env
cd datalabcontainer
docker compose build
docker compose up -d
docker compose exec data-lab bash
su - datalab
```

### First Commands To Try

```bash
datalab_app
datalab_config show
datalab_config detect
datalab_config recommend
datalab_config apply balanced
datalab_app --start-core
datalab_app --status-health
```

### Featured Demo Workflows

CDC:

```bash
datalab_app --setup-postgres-cdc
datalab_app --verify-postgres-cdc
```

Lakehouse analytics:

```bash
datalab_app --start-minio
datalab_app --start-trino
datalab_app --start-superset
```

Quality and notebooks:

```bash
datalab_app --start-quality-stack
datalab_app --run-great-expectations-demo
```

Lineage and monitoring:

```bash
datalab_app --start-observability-stack
datalab_app --run-lineage-demo
```

For standalone runs, system requirements, runtime paths, and reset notes, see [Getting Started](docs/GETTING-STARTED.md).

## What Makes It Portfolio-Ready

- Full-platform thinking: the project connects infrastructure, orchestration, analytics, quality, and observability rather than focusing on one isolated tool.
- Reproducible local environment: a reviewer can run a substantial data platform without provisioning a cloud environment first.
- Clear operational structure: helper scripts, runtime folders, UI discovery, and documentation make the repo easier to navigate and demo.

## Repository Layout

- `datalabcontainer/` - container build files, runtime scripts, and service modules
- `datalabconfig/` - runtime tuning and configuration commands
- `stacks/` - stack-specific notes and service-level READMEs
- `helper/scripts/` - build, run, copy, and cleanup helpers
- `docs/` - setup guides, architecture notes, and reference documentation

## Documentation Map

- [Getting Started](docs/GETTING-STARTED.md)
- [Access Reference](docs/ACCESS-REFERENCE.md)
- [Stack Reference](docs/STACK-REFERENCE.md)
- [Data Lab CLI Guide](docs/DATALAB-APP-CLI.md)
- [Container Topology Guide](docs/CONTAINER-TOPOLOGY-GUIDE.md)
- [Trino Lakehouse Registration Guide](docs/TRINO-LAKEHOUSE-REGISTRATION.md)
- [Hudi Registration Guide](docs/HUDI-REGISTRATION.md)
- [Iceberg Registration Guide](docs/ICEBERG-REGISTRATION.md)
- [Delta Registration Guide](docs/DELTA-REGISTRATION.md)
- [Docker Hub Push/Pull Guide](docs/DOCKERHUB-README.md)
- [Data Engineering Expansion Roadmap](docs/DATA-ENGINEERING-EXPANSION-ROADMAP.md)
- [ML/AI Future Roadmap](docs/ML-AI-FUTURE-ROADMAP.md)

## Current Focus

Data Lab is positioned as a practical local sandbox for demonstrating data engineering platform design:

- service orchestration
- CDC and streaming integration
- lakehouse table access and BI querying
- data quality validation
- lineage and monitoring workflows

That makes it a strong repo for showcasing platform engineering, analytics engineering, and end-to-end data tooling in one place.
