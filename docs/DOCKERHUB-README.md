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

```powershell
docker build -t data-lab:latest -f datalabcontainer/dev/base/Dockerfile .
```

## 3) Tag image for Docker Hub

Replace `<dockerhub-username>` with your Docker Hub username.

```powershell
docker tag data-lab:latest <dockerhub-username>/data-lab:latest
docker tag data-lab:latest <dockerhub-username>/data-lab:v1
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

## 6) Verify local images

```powershell
docker images
```

## 7) Run container from pulled image

```powershell
docker run -d --name datalab -p 8080:8080 <dockerhub-username>/data-lab:latest sleep infinity
```

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

