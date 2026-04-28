# Getting Started

This guide keeps the practical setup details out of the main README while preserving the information needed to run Data Lab locally.

## System Requirements

Minimum:

1. CPU: 4 vCPU
2. RAM: 12 GB
3. Disk: 50 GB free SSD
4. Docker: Docker Desktop or Docker Engine with Compose support

Recommended:

1. CPU: 8 vCPU
2. RAM: 24 GB
3. Disk: 100 GB free SSD
4. Docker Desktop resources: at least 8 CPU and 20+ GB memory

Future-oriented expansion target:

1. CPU: 12 vCPU
2. RAM: 32 GB
3. Disk: 150 GB free SSD

Future-oriented ML/AI profile target:

1. CPU: 12+ vCPU
2. RAM: 32 to 64 GB
3. Disk: 200 GB free SSD
4. Optional GPU: NVIDIA GPU with 12+ GB VRAM

## Start With Docker Compose

```bash
cp datalabcontainer/.env.example datalabcontainer/.env
cd datalabcontainer
docker compose build
docker compose up -d
docker compose exec data-lab bash
su - datalab
```

Useful first commands:

```bash
datalab_app
datalab_config show
datalab_config detect
datalab_config recommend
datalab_config apply balanced
datalab_app --start-core
datalab_app --status-health
datalab_app --health-check-fast
```

## Standalone Launch

Linux or macOS:

```bash
NAME=datalab IMAGE=data-lab:latest ./helper/scripts/run-standalone.sh
```

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\run-standalone.ps1 -Name datalab -Image data-lab:latest
```

These standalone helper commands now publish the default core ports plus the lakehouse/UI ports for Superset (`8090`), Trino (`8091`), MinIO API (`9004`), and MinIO Console (`9005`).

## Runtime Model

- Single container is the default runtime model.
- New capabilities are expected under `datalabcontainer/app/tech/*`.
- Mutable service state lives under `datalabcontainer/runtime/<service>`.
- Services keep stable container ports even when host ports are remapped.

Use `ui_services` and `datalab_app` as the source of truth for outside-host URLs when running copied containers or dynamic port mappings.

## Runtime Data

All mutable state is stored under:

- Host: `datalabcontainer/runtime/`
- Container: `/home/datalab/runtime/`

You can reset a service by removing only its runtime folder, for example:

- `datalabcontainer/runtime/airflow`

## Suggested Next Reads

- [Access Reference](ACCESS-REFERENCE.md)
- [Data Lab CLI Guide](DATALAB-APP-CLI.md)
- [Container Topology Guide](CONTAINER-TOPOLOGY-GUIDE.md)
