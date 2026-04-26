# Docker Hub Push/Pull Guide

This guide shows how to build, tag, push, and pull the Data Lab image with Docker Hub.

## Important image model

`data-lab:latest` is the single runtime image for the full Data Lab platform.

During local builds, Docker may also pull temporary build-source images such as:

- `prom/prometheus`
- `grafana/grafana`
- `marquezproject/marquez`
- `marquezproject/marquez-web`
- `apicurio/apicurio-registry`
- `quay.io/debezium/connect`

These are only multi-stage build sources. They are not separate runtime images you need to push or run for Data Lab.

## Prerequisites

- Docker Desktop (or Docker Engine) is running.
- Docker Hub account is available.
- Repo root is the current directory (`d:\GitHub\Data-Lab`).

## 1) Login to Docker Hub

```powershell
docker login
```

## 2) Build the image locally

You can use either flow below.

### Option A (recommended): build directly with Docker Hub tag

```powershell
docker build -t <dockerhub-username>/data-lab:latest -f datalabcontainer/dev/base/Dockerfile .
```

### Option B: build local tag, then retag for Docker Hub

```powershell
docker build -t data-lab:latest -f datalabcontainer/dev/base/Dockerfile .
docker tag data-lab:latest <dockerhub-username>/data-lab:latest
```

## 3) Optional version tag (recommended)

Replace `<dockerhub-username>` with your Docker Hub username.

```powershell
docker tag <dockerhub-username>/data-lab:latest <dockerhub-username>/data-lab:v1
```

## 4) Push to Docker Hub

```powershell
docker push <dockerhub-username>/data-lab:latest
docker push <dockerhub-username>/data-lab:v1
```

## 5) Pull from Docker Hub

```powershell
docker pull <dockerhub-username>/data-lab:latest
docker pull <dockerhub-username>/data-lab:v1
```

## 6) Verify pushed tag points to the new image

Check image IDs:

```powershell
docker image inspect data-lab:latest --format "{{.Id}}"
docker image inspect <dockerhub-username>/data-lab:latest --format "{{.Id}}"
```

If these IDs differ, retag and push again:

```powershell
docker tag data-lab:latest <dockerhub-username>/data-lab:latest
docker push <dockerhub-username>/data-lab:latest
```

## 7) Verify local images

```powershell
docker images
```

## 8) Run container from pulled image

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
  -p 9083:9083 `
  -p 10000:10000 `
  -p 10001:10001 `
  -p 9002:9002 `
  -p 9004:9004 `
  -p 9005:9005 `
  -p 8083:8083 `
  -p 8084:8084 `
  -p 8085:8085 `
  -p 8086:8086 `
  -p 8181:8181 `
  -p 8888:8888 `
  -p 8891:8891 `
  -p 5000:5000 `
  -p 3000:3000 `
  -p 9095:9095 `
  -p 3001:3001 `
  -p 5432:5432 `
  -p 27017:27017 `
  -p 6379:6379 `
  <dockerhub-username>/data-lab:latest `
  sleep infinity
```

## Common mistake (important)

If you build only `data-lab:latest` and then run `docker push <dockerhub-username>/data-lab:latest` without retagging, Docker pushes whatever old image is currently attached to the Docker Hub tag. That is why `docker pull` can still say "up to date" while your new changes are missing.

## Optional: Use existing helper scripts

Run container directly from Docker Hub image:

```powershell
powershell -File .\helper\scripts\run-standalone.ps1 -Name datalab -Image <dockerhub-username>/data-lab:latest
```

That helper now includes the default lakehouse/UI ports automatically, so Superset, Trino, and MinIO are reachable without adding extra port flags.

Copy container from Docker Hub image:

```powershell
powershell -File .\helper\scripts\copy-container.ps1 -NewName datalab-copy -Image <dockerhub-username>/data-lab:latest -ForcePull
```

## Quick cleanup commands

Remove dangling images (`<none>`):

```powershell
docker image prune -f
```

Remove unused images/containers/networks:

```powershell
docker system prune -f
```

Remove only the known Data Lab build-source images after `data-lab:latest` is built:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\cleanup-build-source-images.ps1
```

Dry run first:

```powershell
powershell -ExecutionPolicy Bypass -File .\helper\scripts\cleanup-build-source-images.ps1 -DryRun
```

Linux/macOS:

```bash
bash ./helper/scripts/cleanup-build-source-images.sh
```

