# Docker Hub Push/Pull Guide

This guide shows how to build, tag, push, and pull the Data Lab image with Docker Hub.

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
docker run -d --name datalab -p 8080:8080 <dockerhub-username>/data-lab:latest sleep infinity
```

## Common mistake (important)

If you build only `data-lab:latest` and then run `docker push <dockerhub-username>/data-lab:latest` without retagging, Docker pushes whatever old image is currently attached to the Docker Hub tag. That is why `docker pull` can still say "up to date" while your new changes are missing.

## Optional: Use existing helper scripts

Run container directly from Docker Hub image:

```powershell
powershell -File .\helper\scripts\run-standalone.ps1 -Name datalab -Image <dockerhub-username>/data-lab:latest
```

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

