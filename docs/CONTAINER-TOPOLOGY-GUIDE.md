# Data Lab Container Topology Guide

This guide compares two deployment styles for this project:

1. Single-container (current non-stackable model)
2. Multi-container (service-per-container model)

## Quick Decision

Use single-container when you need:

1. Fast local setup
2. Easy demos and teaching
3. One command start/stop
4. Minimal infra overhead

Use multi-container when you need:

1. Better reliability and isolation
2. Independent scaling per service
3. Production-like operations
4. Easier troubleshooting by service boundaries

## Trade-off Summary

| Area | Single-container | Multi-container |
| --- | --- | --- |
| Setup speed | Fastest | Slower |
| Learning/demo UX | Best | Good |
| Service isolation | Low | High |
| Failure blast radius | High | Lower |
| Horizontal scaling | Limited | Better |
| Upgrade flexibility | Coupled | Decoupled |
| Resource tuning | Shared | Per-service |
| Operational complexity | Low | Higher |

## Hardware Requirements

These profiles are practical guidance for this repo.

### Minimum (single-container development)

1. CPU: 4 vCPU
2. RAM: 12 GB
3. Disk: 50 GB free SSD
4. Notes: start only needed services when resources are tight.

### Recommended (single-container full stack)

1. CPU: 8 vCPU
2. RAM: 24 GB
3. Disk: 100 GB free SSD
4. Notes: suitable for running most services together with better stability.

### Future target (ML/AI expansion profile)

1. CPU: 12+ vCPU
2. RAM: 32 to 64 GB
3. Disk: 200 GB free SSD
4. Optional GPU: NVIDIA GPU with 12+ GB VRAM for local LLM serving.

### Multi-container guidance

1. Start with the same total resources as recommended single-container.
2. Increase capacity by service bottleneck (for example Spark workers, Trino workers, or model serving).
3. Keep per-service CPU/memory limits explicit in compose files to avoid noisy-neighbor issues.

## Recommendation For This Repo

Keep both modes:

1. `dev/demo` profile: single-container (current default)
2. `scale/prod-like` profile: multi-container (future addition)

This keeps current simplicity while allowing a clean path for heavier workloads.

## Migration Triggers

Move from single-container to multi-container when one or more happen:

1. Frequent resource contention between Spark, Airflow, Trino, and DB services
2. Need to scale a specific service without scaling all others
3. Need stronger uptime and fault isolation
4. Team workflow requires clearer ownership per service
5. CI/CD needs independent release cycles for core services

## Suggested Future Multi-Container Split

Start with this minimal separation:

1. Orchestration: Airflow
2. Compute: Spark master/worker
3. Lakehouse query: Trino
4. Metadata: Hive metastore
5. Storage services: PostgreSQL, MongoDB, Redis, MinIO
6. UI layer: Superset, pgAdmin, Mongo Express, Redis Commander

## Notes For Current State

1. Current single-container remains valid for ETL, lakehouse demos, and development.
2. Airflow parallel task state and Spark real execution capacity are separate limits.
3. This document is planning guidance only and does not change runtime behavior.

## References

1. Docker best practices: https://docs.docker.com/engine/userguide/eng-image/dockerfile_best-practices/
2. Docker multi-container apps: https://docs.docker.com/get-started/docker-concepts/running-containers/multi-container-applications/
3. Airflow architecture overview: https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/overview.html
4. Trino deployment: https://trino.io/docs/current/installation/deployment.html
