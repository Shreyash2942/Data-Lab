# Standalone Run Guide

This guide replaces the older long-form standalone README with a cleaner reference for running Data Lab without Docker Compose stack labels.

## When To Use Standalone Mode

Standalone mode is a good fit when you want:

- one direct `docker run` workflow
- helper-script-based setup from the repo root
- easy cloning of containers with remapped host ports
- a simpler local demo path for portfolio or interview walkthroughs

## Quick Start

### Build Locally

```bash
docker build -t data-lab:latest .
```

### Pull Instead Of Build

```bash
docker pull shreyash42/data-lab:latest
```

### Run On Linux Or macOS

```bash
NAME=datalab IMAGE=data-lab:latest ./helper/scripts/run-standalone.sh
```

### Run On Windows PowerShell

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\run-standalone.ps1 -Name datalab -Image data-lab:latest
```

## Common Helper Workflows

### Build And Run In One Step

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\build-and-run.ps1 -Name datalab -Image data-lab:latest
```

### Copy An Existing Container

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\copy-container.ps1 -SourceName datalab
```

### Show Real Mapped URLs

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name datalab -UiHost localhost
```

### Open A Shell In The Container

```bash
docker exec -it -w / datalab bash
```

### Switch To The Development User

```bash
su - datalab
```

## Inside The Container

Start the interactive service launcher:

```bash
datalab_app
```

Start database services:

```bash
datalab_app --start-databases
```

Start the database browser UIs:

```bash
datalab_app --start-db-uis
```

Open the interactive UI helper:

```bash
ui_services
```

Print all mapped URLs:

```bash
ui_services --list
```

Show current runtime tuning:

```bash
datalab_config show
```

Detect recommended tuning:

```bash
datalab_config detect
```

Apply the balanced tuning profile:

```bash
datalab_config apply balanced
```

## Database UI And Access Flow

Start the database stack:

```bash
datalab_app --start-databases
```

Start the bundled database browser UIs:

```bash
datalab_app --start-db-uis
```

From the host, print the mapped URLs:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\ui-services.ps1 -Name datalab -UiHost localhost
```

If you want the separate official pgAdmin container:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\start-pgadmin.ps1 -TargetContainer datalab -PgAdminPort 8181
```

Current browser defaults:

- pgAdmin: `admin@admin.com / admin`
- MinIO: `minio_admin / minioadmin`
- Grafana: `admin / admin`
- Jupyter token: `datalab`

For the rest of the URLs and default credentials, see [Access Reference](ACCESS-REFERENCE.md).

## Manual Docker Run

Use this only when you want to bypass the helper scripts completely.

### Linux Or macOS

```bash
docker run -d --name datalab \
  --user root \
  --workdir / \
  --label com.docker.compose.project= \
  --label com.docker.compose.service= \
  --label com.docker.compose.oneoff= \
  -p 8080:8080 \
  -p 4040:4040 \
  -p 9090:9090 \
  -p 18080:18080 \
  -p 9092:9092 \
  -p 9870:9870 \
  -p 8088:8088 \
  -p 8090:8090 \
  -p 8091:8091 \
  -p 10000:10000 \
  -p 10001:10001 \
  -p 9002:9002 \
  -p 9004:9004 \
  -p 9005:9005 \
  -p 8083:8083 \
  -p 8084:8084 \
  -p 8181:8181 \
  -p 5432:5432 \
  -p 27017:27017 \
  -p 6379:6379 \
  shreyash42/data-lab:latest \
  sleep infinity
```

### Windows PowerShell

```powershell
docker run -d --name datalab `
  --user root `
  --workdir / `
  --label com.docker.compose.project= `
  --label com.docker.compose.service= `
  --label com.docker.compose.oneoff= `
  -p 8080:8080 `
  -p 4040:4040 `
  -p 9090:9090 `
  -p 18080:18080 `
  -p 9092:9092 `
  -p 9870:9870 `
  -p 8088:8088 `
  -p 8090:8090 `
  -p 8091:8091 `
  -p 10000:10000 `
  -p 10001:10001 `
  -p 9002:9002 `
  -p 9004:9004 `
  -p 9005:9005 `
  -p 8083:8083 `
  -p 8084:8084 `
  -p 8181:8181 `
  -p 5432:5432 `
  -p 27017:27017 `
  -p 6379:6379 `
  shreyash42/data-lab:latest `
  sleep infinity
```

## Operational Notes

- Default mounts map the repo folders into `/home/datalab/...` plus `runtime` for state persistence.
- Add extra mounts with `EXTRA_VOLUMES` in bash or `-ExtraVolumes` in PowerShell.
- Helper-based copy flows are the safer choice when you want multiple containers because they auto-resolve port conflicts.
- Log retention runs automatically before `start` and `restart` commands.
- Optional log tuning environment variables include `DATALAB_LOG_RETENTION_ENABLED`, `DATALAB_LOG_RETENTION_MAX_TOTAL_MB`, `DATALAB_LOG_RETENTION_MAX_FILES`, and `DATALAB_LOG_RETENTION_FILE_PATTERNS`.

Manual log pruning:

```bash
bash /home/datalab/app/start --prune-logs
```

## Related Docs

- [Main README](../README.md)
- [Getting Started](GETTING-STARTED.md)
- [Access Reference](ACCESS-REFERENCE.md)
- [Data Lab CLI Guide](DATALAB-APP-CLI.md)
- [Helper Scripts Reference](../helper/scripts/README.md)
- [PostgreSQL Stack Guide](../stacks/postgres/README.md)
- [MongoDB Stack Guide](../stacks/mongodb/README.md)
- [Redis Stack Guide](../stacks/redis/README.md)
